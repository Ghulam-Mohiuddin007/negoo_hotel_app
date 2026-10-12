-- ==============================================================================
-- NEGOO & NEGOO HOTEL APP: SUPABASE DATABASE OPTIMIZATION & INDEXING SCHEMA
-- ==============================================================================
-- Purpose:
-- 1. High-Performance Indexing across all query paths for sub-millisecond lookups
-- 2. Pure Supabase Realtime Notification Configuration (FCM-free architecture)
-- 3. Proximity Location Function ('get_nearby_hotels') for Explore Screen
-- 4. Automatic Replication & Realtime Channel publication for instant state sync
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. EXTENSIONS
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ------------------------------------------------------------------------------
-- 2. NOTIFICATIONS TABLE (Pure Supabase In-App & Realtime Notification Hub)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    hotel_id UUID,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    type TEXT DEFAULT 'bid_event',
    data JSONB DEFAULT '{}'::jsonb,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Row Level Security (RLS) on Notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated users to read their own notifications"
ON public.notifications FOR SELECT TO authenticated
USING (
    auth.uid() = user_id 
    OR auth.uid() = hotel_id
);

CREATE POLICY "Allow authenticated users/hotels to insert notifications"
ON public.notifications FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "Allow updating read status"
ON public.notifications FOR UPDATE TO authenticated
USING (
    auth.uid() = user_id 
    OR auth.uid() = hotel_id
);

-- ------------------------------------------------------------------------------
-- 3. PERFORMANCE INDEXES
-- ------------------------------------------------------------------------------

-- [TABLE: bids] - Live Bidding Engine Optimization
-- Speeds up Live Incoming Offers stream: .from('bids').eq('hotel_id', id).eq('status', 'pending')
CREATE INDEX IF NOT EXISTS idx_bids_hotel_status 
ON public.bids (hotel_id, status);

-- Speeds up User Bidding monitor: .from('bids').eq('user_id', id).eq('status', 'pending')
CREATE INDEX IF NOT EXISTS idx_bids_user_status 
ON public.bids (user_id, status);

-- Speeds up room specific bids and expired sweeps
CREATE INDEX IF NOT EXISTS idx_bids_room_id 
ON public.bids (room_id);

CREATE INDEX IF NOT EXISTS idx_bids_expires_at 
ON public.bids (expires_at) 
WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_bids_created_at_desc 
ON public.bids (created_at DESC);

-- [TABLE: bookings] - Financials, History, & Receipts
-- Speeds up User Booking History: .from('bookings').eq('user_id', id).order('created_at', desc)
CREATE INDEX IF NOT EXISTS idx_bookings_user_id_created 
ON public.bookings (user_id, created_at DESC);

-- Speeds up Hotel Financial Matrix joins: .from('bookings').eq('rooms.hotel_id', id)
CREATE INDEX IF NOT EXISTS idx_bookings_room_id 
ON public.bookings (room_id);

-- Optional hotel_id direct filter on bookings if column exists
DO $$ 
BEGIN 
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'bookings' 
          AND column_name = 'hotel_id'
    ) THEN 
        CREATE INDEX IF NOT EXISTS idx_bookings_hotel_id ON public.bookings (hotel_id);
    END IF; 
END $$;

CREATE INDEX IF NOT EXISTS idx_bookings_status 
ON public.bookings (status);

CREATE INDEX IF NOT EXISTS idx_bookings_created_at_desc 
ON public.bookings (created_at DESC);

-- Foreign Key constraint check for inner join queries: rooms!fk_room(...)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_room'
    ) THEN
        BEGIN
            ALTER TABLE public.bookings 
            ADD CONSTRAINT fk_room 
            FOREIGN KEY (room_id) REFERENCES public.rooms(id) ON DELETE CASCADE;
        EXCEPTION WHEN duplicate_object THEN
            NULL;
        WHEN OTHERS THEN
            NULL;
        END;
    END IF;
END $$;

-- [TABLE: rooms] - Inventory & Listing Optimization
-- Speeds up fetching room inventory by hotel: .from('rooms').eq('hotel_id', id)
CREATE INDEX IF NOT EXISTS idx_rooms_hotel_id 
ON public.rooms (hotel_id);

-- Speeds up price filtering and room availability checks
CREATE INDEX IF NOT EXISTS idx_rooms_price 
ON public.rooms (price);

DO $$ 
BEGIN 
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'rooms' 
          AND column_name = 'is_available'
    ) THEN 
        CREATE INDEX IF NOT EXISTS idx_rooms_hotel_available ON public.rooms (hotel_id, is_available);
    END IF; 
END $$;

-- [TABLE: hotels] - Explore, Nearby Search, & Auth Verification
-- Speeds up hotel login and approval gates: .eq('is_approved', true)
CREATE INDEX IF NOT EXISTS idx_hotels_is_approved 
ON public.hotels (is_approved);

-- Speeds up owner lookup: .eq('owner_id', id)
DO $$ 
BEGIN 
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'hotels' 
          AND column_name = 'owner_id'
    ) THEN 
        CREATE INDEX IF NOT EXISTS idx_hotels_owner_id ON public.hotels (owner_id);
    END IF; 
END $$;

-- Spatial GIST index for lightning-fast location radius searches (if location column exists)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'hotels' 
          AND column_name = 'location'
    ) THEN
        BEGIN
            CREATE INDEX IF NOT EXISTS idx_hotels_location ON public.hotels USING GIST (location);
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;
END $$;

-- [TABLE: favorites] - Fast Room Favoriting Lookups
CREATE UNIQUE INDEX IF NOT EXISTS idx_favorites_user_room 
ON public.favorites (user_id, room_id);

CREATE INDEX IF NOT EXISTS idx_favorites_room_id 
ON public.favorites (room_id);

-- [TABLE: profiles] - User Profile Quick Lookups
CREATE INDEX IF NOT EXISTS idx_profiles_id 
ON public.profiles (id);

-- [TABLE: notifications] - Realtime Feed Optimization
CREATE INDEX IF NOT EXISTS idx_notifications_user_id 
ON public.notifications (user_id, is_read, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_hotel_id 
ON public.notifications (hotel_id, is_read, created_at DESC);

-- ------------------------------------------------------------------------------
-- 4. SUPABASE REALTIME CONFIGURATION (Push & Realtime without Firebase)
-- ------------------------------------------------------------------------------

-- Ensure full row payload is transmitted to client WebSockets on row mutations
ALTER TABLE public.bids REPLICA IDENTITY FULL;
ALTER TABLE public.bookings REPLICA IDENTITY FULL;
ALTER TABLE public.notifications REPLICA IDENTITY FULL;

-- Add tables to supabase_realtime publication
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.bids;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.bookings;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.rooms;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.hotels;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
END $$;

-- ------------------------------------------------------------------------------
-- 5. RPC FUNCTION: get_nearby_hotels (For User App Explore View)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_nearby_hotels(
    user_lat DOUBLE PRECISION,
    user_long DOUBLE PRECISION,
    radius_meters DOUBLE PRECISION DEFAULT 50000.0
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    hotel_name TEXT,
    rating NUMERIC,
    image_url TEXT,
    city TEXT,
    address TEXT,
    dist_meters DOUBLE PRECISION
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Check if spatial location column exists
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'hotels' 
          AND column_name = 'location'
    ) THEN
        RETURN QUERY
        SELECT 
            h.id,
            COALESCE(h.name, 'Hotel')::TEXT,
            COALESCE(h.hotel_name, h.name, 'Hotel')::TEXT,
            COALESCE(h.rating, 4.5)::NUMERIC,
            h.image_url::TEXT,
            h.city::TEXT,
            h.address::TEXT,
            ST_Distance(
                h.location::geography, 
                ST_SetSRID(ST_MakePoint(user_long, user_lat), 4326)::geography
            ) AS dist_meters
        FROM public.hotels h
        WHERE h.is_approved = true
          AND (
              h.location IS NULL 
              OR ST_DWithin(
                  h.location::geography, 
                  ST_SetSRID(ST_MakePoint(user_long, user_lat), 4326)::geography, 
                  radius_meters
              )
          )
        ORDER BY dist_meters ASC NULLS LAST
        LIMIT 50;
    ELSE
        -- Fallback if location column is not yet geographic
        RETURN QUERY
        SELECT 
            h.id,
            COALESCE(h.name, 'Hotel')::TEXT,
            COALESCE(h.hotel_name, h.name, 'Hotel')::TEXT,
            COALESCE(h.rating, 4.5)::NUMERIC,
            h.image_url::TEXT,
            h.city::TEXT,
            h.address::TEXT,
            0.0::DOUBLE PRECISION AS dist_meters
        FROM public.hotels h
        WHERE h.is_approved = true
        LIMIT 50;
    END IF;
END;
$$;

-- Grant execution privilege to anon and authenticated clients
GRANT EXECUTE ON FUNCTION public.get_nearby_hotels TO anon, authenticated, service_role;

-- ------------------------------------------------------------------------------
-- 6. AUTOMATED BID EXPIRATION CRON HELPER (Optional PostgreSQL Function)
-- ------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.expire_stale_bids()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.bids
    SET status = 'expired'
    WHERE status = 'pending'
      AND expires_at < now();
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. GUEST ARCHIVE TABLE & PERFORMANCE INDEXES FOR FRONT DESK CHECK-OUT
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.guest_archive (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id TEXT NOT NULL,
    hotel_id UUID,
    user_id UUID,
    full_name TEXT,
    phone TEXT,
    cnic TEXT,
    room_type TEXT,
    total_price NUMERIC,
    stay_from TEXT,
    stay_to TEXT,
    payment_method TEXT,
    payment_status TEXT DEFAULT 'paid',
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ DEFAULT now()
);

-- Fast indexing for instant customer retrieval by phone, cnic, booking id, and hotel
CREATE INDEX IF NOT EXISTS idx_guest_archive_hotel_id ON public.guest_archive (hotel_id);
CREATE INDEX IF NOT EXISTS idx_guest_archive_booking_id ON public.guest_archive (booking_id);
CREATE INDEX IF NOT EXISTS idx_guest_archive_phone ON public.guest_archive (phone);
CREATE INDEX IF NOT EXISTS idx_guest_archive_cnic ON public.guest_archive (cnic);

-- Performance Indexes on bookings for Front Desk quick-search
CREATE INDEX IF NOT EXISTS idx_bookings_phone ON public.bookings (phone);
CREATE INDEX IF NOT EXISTS idx_bookings_cnic ON public.bookings (cnic);

-- ------------------------------------------------------------------------------
-- 8. NEGOO COMMISSION SETTLEMENT & SUPERADMIN GOVERNANCE SCHEMA
-- ------------------------------------------------------------------------------
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS commission_paid BOOLEAN DEFAULT false;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS commission_status TEXT DEFAULT 'unpaid';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS commission_settled_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS commission_verified_by TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS remittance_ref TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS remittance_status TEXT DEFAULT 'pending_superadmin_verification';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS remittance_submitted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_bookings_commission_status ON public.bookings (commission_status);
CREATE INDEX IF NOT EXISTS idx_bookings_commission_paid ON public.bookings (commission_paid);
CREATE INDEX IF NOT EXISTS idx_bookings_remittance_ref ON public.bookings (remittance_ref);

-- ------------------------------------------------------------------------------
-- 9. FRONT DESK LIFECYCLE & PAYMENT EXTENSIONS ON BOOKINGS
-- ------------------------------------------------------------------------------
-- Ensures instant compatibility with Front Desk operations without schema cache errors
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS checked_out_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS is_paid BOOLEAN DEFAULT false;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS payment_received_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_bookings_is_paid ON public.bookings (is_paid);
CREATE INDEX IF NOT EXISTS idx_bookings_payment_status ON public.bookings (payment_status);
CREATE INDEX IF NOT EXISTS idx_bookings_checked_out_at ON public.bookings (checked_out_at);



