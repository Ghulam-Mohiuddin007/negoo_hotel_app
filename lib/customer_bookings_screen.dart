import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:negoo_hotel_app/services/cache_service.dart';
import 'package:negoo_hotel_app/services/database_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerBookingsScreen extends StatefulWidget {
  final String userId;
  const CustomerBookingsScreen({super.key, required this.userId});

  @override
  State<CustomerBookingsScreen> createState() => _CustomerBookingsScreenState();
}

class _CustomerBookingsScreenState extends State<CustomerBookingsScreen> {
  late final SupabaseClient _supabase;
  final BookingCacheService _cacheService = BookingCacheService();
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _filteredBookings = [];
  bool _isLoading = true;
  String _activeFilter = 'all'; // 'all', 'pending', 'confirmed', 'checked_in', 'checked_out'
  String _hotelName = "Hotel Partner";
  RealtimeChannel? _liveFeedChannel;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _fetchHotelName();
    _loadBookingsFast();
    _subscribeToLiveBookings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_liveFeedChannel != null) {
      _supabase.removeChannel(_liveFeedChannel!);
    }
    super.dispose();
  }

  /// Subscribe to Realtime Supabase changes on bookings table
  void _subscribeToLiveBookings() {
    try {
      _liveFeedChannel = _supabase
          .channel('hotel_bookings_frontdesk_${widget.userId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                HapticFeedback.heavyImpact();
                ToastService.info("⚡ New Booking Received! Tap to confirm.");
              }
              _fetchServerBookings(showLoading: false);
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _fetchHotelName() async {
    try {
      final data = await _supabase
          .from('hotels')
          .select('hotel_name, name')
          .eq('id', widget.userId)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _hotelName = data['hotel_name'] ?? data['name'] ?? "Hotel Partner";
        });
      }
    } catch (_) {}
  }

  /// 1. Load instantly from cache memory, then sync with server in background
  Future<void> _loadBookingsFast() async {
    final cached = await _cacheService.getCachedBookings(widget.userId);
    if (cached.isNotEmpty && mounted) {
      setState(() {
        _allBookings = cached;
        _applyFilterAndSearch();
        _isLoading = false;
      });
    }

    await _fetchServerBookings(showLoading: cached.isEmpty);
  }

  /// 2. Fetch fresh records from Supabase via DatabaseService and update cache
  Future<void> _fetchServerBookings({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _isLoading = true);

    try {
      final freshList = await _databaseService.fetchHotelBookings(widget.userId);

      await _cacheService.cacheBookings(widget.userId, freshList);

      if (mounted) {
        setState(() {
          _allBookings = freshList;
          _applyFilterAndSearch();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching bookings: $e");
      if (mounted && showLoading) setState(() => _isLoading = false);
    }
  }

  void _applyFilterAndSearch() {
    List<Map<String, dynamic>> workingList = _allBookings;

    // Apply Filter Tab
    if (_activeFilter == 'pending') {
      workingList = workingList.where((b) => b['status'] == 'pending').toList();
    } else if (_activeFilter == 'confirmed') {
      workingList = workingList.where((b) => b['status'] == 'confirmed').toList();
    } else if (_activeFilter == 'checked_in') {
      workingList = workingList.where((b) => b['status'] == 'checked_in').toList();
    } else if (_activeFilter == 'checked_out') {
      workingList = workingList.where((b) => b['status'] == 'checked_out').toList();
    }

    // Apply O(1) Memory Index Search
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _filteredBookings = _cacheService.searchBookings(query, workingList);
    } else {
      _filteredBookings = workingList;
    }
  }

  // ===========================================================================
  // FRONT DESK ACTIONS: CONFIRM, CHECK-IN, RECEIVE PAYMENT, CHECK-OUT & ARCHIVE
  // ===========================================================================

  /// Action 1: Confirm Booking Immediately
  Future<void> _confirmBooking(Map<String, dynamic> booking) async {
    final bookingId = booking['id'].toString();
    final guestUserId = booking['user_id']?.toString();
    final roomData = booking['rooms'] as Map<String, dynamic>?;
    final roomType = roomData?['room_type'] ?? 'Standard Room';

    HapticFeedback.mediumImpact();

    final success = await _databaseService.confirmBooking(
      bookingId: bookingId,
      guestUserId: guestUserId,
      hotelName: _hotelName,
      roomType: roomType,
    );

    if (success) {
      ToastService.success("Booking confirmed! Guest has been notified.");
      _fetchServerBookings(showLoading: false);
    } else {
      ToastService.error("Failed to confirm booking. Please try again.");
    }
  }

  /// Action 2: Check-In Guest
  Future<void> _checkInGuest(Map<String, dynamic> booking) async {
    final bookingId = booking['id'].toString();
    final guestUserId = booking['user_id']?.toString();

    HapticFeedback.lightImpact();

    final success = await _databaseService.checkInGuest(
      bookingId: bookingId,
      guestUserId: guestUserId,
      hotelName: _hotelName,
    );

    if (success) {
      ToastService.success("Guest marked as Checked-In! 🏨");
      _fetchServerBookings(showLoading: false);
    } else {
      ToastService.error("Failed to check-in guest.");
    }
  }

  /// Action 3: Record / Mark Payment Received
  Future<void> _recordPaymentReceived(Map<String, dynamic> booking, String method) async {
    final bookingId = booking['id'].toString();

    final success = await _databaseService.recordPaymentReceived(
      bookingId: bookingId,
      method: method,
    );

    if (success) {
      ToastService.success("Payment recorded as RECEIVED ($method)! 💰");
      _fetchServerBookings(showLoading: false);
    } else {
      ToastService.error("Payment update failed.");
    }
  }

  /// Action 4: Check-Out Guest & Archive Customer Data Into Dedicated Table
  Future<void> _checkOutAndArchiveGuest(Map<String, dynamic> booking) async {
    final bookingId = booking['id'].toString();
    final now = DateTime.now().toIso8601String();
    final roomData = booking['rooms'] as Map<String, dynamic>?;
    final roomType = roomData?['room_type'] ?? 'Standard Room';

    try {
      // 1. Update Booking row status to checked_out
      await _supabase
          .from('bookings')
          .update({
            'status': 'checked_out',
            'checked_out_at': now,
          })
          .eq('id', bookingId);

      // 2. Prepare payload to save in the dedicated 'guest_archive' table
      final archivePayload = {
        'booking_id': BookingCacheService.formatUniqueBookingId(bookingId),
        'hotel_id': widget.userId,
        'user_id': booking['user_id']?.toString(),
        'full_name': booking['full_name'] ?? 'Guest',
        'phone': booking['phone'] ?? 'N/A',
        'cnic': booking['cnic'] ?? 'N/A',
        'room_type': roomType,
        'total_price': booking['total_price'],
        'stay_from': booking['stay_from'] ?? '',
        'stay_to': booking['stay_to'] ?? '',
        'payment_method': booking['payment_method'] ?? 'cash',
        'payment_status': booking['payment_status'] ?? 'received',
        'checked_in_at': booking['checked_in_at'] ?? now,
        'checked_out_at': now,
        'archived_at': now,
      };

      // 3. Attempt insert into guest_archive table via DatabaseService
      await _databaseService.archiveGuestRecord(archivePayload);

      // 4. Save into persistent local archive cache for instant offline retrieval
      await _cacheService.cacheArchivedRecord(widget.userId, archivePayload);

      ToastService.success("Guest checked out & archived into database! 🗄️");
      _fetchServerBookings(showLoading: false);
    } catch (e) {
      ToastService.error("Check-out error: $e");
    }
  }

  Future<void> _updateBookingStatus(Map<String, dynamic> booking, String targetStatus) async {
    try {
      await _supabase.from('bookings').update({'status': targetStatus}).eq('id', booking['id']);
      ToastService.info("Booking marked as $targetStatus");
      _fetchServerBookings(showLoading: false);
    } catch (e) {
      ToastService.error("Status update error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _allBookings.where((b) => b['status'] == 'pending').length;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar - wrapped in Expanded to prevent pixel overflow
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Front Desk Bookings",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Guest Lifecycle • Instant Confirmation • Payment • Archive",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFFD4AF37)),
                    tooltip: "Sync Bookings",
                    onPressed: () => _fetchServerBookings(showLoading: true),
                  ),
                ],
              ),
            ),

            // Pending Bookings Alert Banner (When guests book rooms)
            if (pendingCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: InkWell(
                  onTap: () => setState(() {
                    _activeFilter = 'pending';
                    _applyFilterAndSearch();
                  }),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: Color(0xFFD4AF37), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "$pendingCount New Booking${pendingCount > 1 ? 's' : ''} Received! Tap to confirm immediately.",
                            style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFD4AF37), size: 12),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 6),

            // Search Bar with Inverted Index (Search by Unique ID, Name, Phone, CNIC)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() => _applyFilterAndSearch()),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Search by Unique ID (e.g. NEG-BK-...), Name, Phone, CNIC...",
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFD4AF37), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _applyFilterAndSearch());
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF141418),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Filter Chips - scrollable horizontally to prevent overflow
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildChip('all', "All (${_allBookings.length})"),
                    const SizedBox(width: 8),
                    _buildChip(
                      'pending',
                      "Pending ($pendingCount)",
                      badgeColor: Colors.amberAccent,
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'confirmed',
                      "Confirmed (${_allBookings.where((b) => b['status'] == 'confirmed').length})",
                      badgeColor: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'checked_in',
                      "In-House (${_allBookings.where((b) => b['status'] == 'checked_in').length})",
                      badgeColor: Colors.greenAccent,
                    ),
                    const SizedBox(width: 8),
                    _buildChip(
                      'checked_out',
                      "Archived (${_allBookings.where((b) => b['status'] == 'checked_out').length})",
                      badgeColor: Colors.purpleAccent,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),

            // Bookings List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                  : _filteredBookings.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _filteredBookings.length,
                          itemBuilder: (context, index) {
                            final booking = _filteredBookings[index];
                            return _buildCustomerBookingCard(booking);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String filterKey, String label, {Color? badgeColor}) {
    final bool isSelected = _activeFilter == filterKey;
    return InkWell(
      onTap: () => setState(() {
        _activeFilter = filterKey;
        _applyFilterAndSearch();
      }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFF141418),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4AF37)
                : (badgeColor?.withValues(alpha: 0.3) ?? Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : (badgeColor ?? Colors.white70),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Customer Booking Card with Unique ID, Details, and Front Desk Controls
  Widget _buildCustomerBookingCard(Map<String, dynamic> booking) {
    final rawId = booking['id']?.toString() ?? '';
    final uniqueId = BookingCacheService.formatUniqueBookingId(rawId);
    final roomData = booking['rooms'] as Map<String, dynamic>?;
    final roomType = roomData?['room_type'] ?? 'Standard Suite';
    final status = booking['status']?.toString().toLowerCase() ?? 'pending';
    final bool isPaid = booking['is_paid'] == true ||
        booking['payment_status'] == 'received' ||
        booking['payment_status'] == 'paid';
    final price = booking['total_price'] ?? '0';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: status == 'pending'
              ? const Color(0xFFD4AF37).withValues(alpha: 0.5)
              : status == 'checked_in'
                  ? Colors.greenAccent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.05),
          width: status == 'pending' ? 1.5 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Unique Booking ID & Status Badges
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: uniqueId));
                      ToastService.info("Copied $uniqueId to clipboard");
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tag, size: 12, color: Color(0xFFD4AF37)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              uniqueId,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD4AF37),
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.copy_rounded, size: 11, color: Colors.white.withValues(alpha: 0.4)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Payment Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPaid
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isPaid ? "PAID" : "UNPAID",
                        style: TextStyle(
                          color: isPaid ? Colors.greenAccent : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildLifecycleBadge(status),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Guest & Stay Info
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  child: const Icon(Icons.person, color: Color(0xFFD4AF37), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking['full_name'] ?? 'Guest Traveler',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "$roomType • PKR $price",
                        style: const TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_outlined, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                              const SizedBox(width: 4),
                              Text(
                                booking['phone'] ?? 'No phone',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.badge_outlined, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                              const SizedBox(width: 4),
                              Text(
                                booking['cnic'] ?? 'CNIC N/A',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.date_range, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              "${booking['stay_from'] ?? 'N/A'} ➔ ${booking['stay_to'] ?? 'N/A'}",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),

            // ==========================================
            // FRONT DESK ACTION BUTTONS
            // ==========================================
            _buildActionButtons(booking, status, isPaid),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> booking, String status, bool isPaid) {
    if (status == 'pending') {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _updateBookingStatus(booking, 'rejected'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => _confirmBooking(booking),
              icon: const Icon(Icons.bolt_rounded, size: 17),
              label: const Text("⚡ CONFIRM BOOKING NOW", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 2,
              ),
            ),
          ),
        ],
      );
    }

    if (status == 'confirmed') {
      return Row(
        children: [
          if (!isPaid)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showPaymentMethodSheet(booking),
                icon: const Icon(Icons.payments_outlined, size: 14),
                label: const Text("Receive Pay", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.greenAccent,
                  side: BorderSide(color: Colors.greenAccent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          if (!isPaid) const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _checkInGuest(booking),
              icon: const Icon(Icons.login_rounded, size: 14),
              label: const Text("MARK CHECK-IN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      );
    }

    if (status == 'checked_in') {
      return Row(
        children: [
          if (!isPaid)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showPaymentMethodSheet(booking),
                icon: const Icon(Icons.payments_outlined, size: 14),
                label: const Text("Collect Bill", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amberAccent,
                  side: BorderSide(color: Colors.amberAccent.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          if (!isPaid) const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _checkOutAndArchiveGuest(booking),
              icon: const Icon(Icons.logout_rounded, size: 14),
              label: const Text("CHECK-OUT & ARCHIVE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      );
    }

    // Checked out / Archived
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, color: Colors.purpleAccent, size: 14),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              "COMPLETED & ARCHIVED IN GUEST DATABASE",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentMethodSheet(Map<String, dynamic> booking) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141418),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Record Guest Payment",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Total Bill: PKR ${booking['total_price']}",
              style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _buildPayMethodTile("Cash at Front Desk", Icons.money, () {
              Navigator.pop(context);
              _recordPaymentReceived(booking, 'cash');
            }),
            _buildPayMethodTile("POS Credit / Debit Card", Icons.credit_card, () {
              Navigator.pop(context);
              _recordPaymentReceived(booking, 'card');
            }),
            _buildPayMethodTile("Bank Transfer / EasyPaisa", Icons.account_balance, () {
              Navigator.pop(context);
              _recordPaymentReceived(booking, 'transfer');
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPayMethodTile(String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFD4AF37)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildLifecycleBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'checked_in':
        color = Colors.greenAccent;
        label = "IN-HOUSE";
        break;
      case 'checked_out':
        color = Colors.purpleAccent;
        label = "CHECKED-OUT";
        break;
      case 'confirmed':
        color = Colors.blueAccent;
        label = "CONFIRMED";
        break;
      case 'rejected':
        color = Colors.redAccent;
        label = "DECLINED";
        break;
      default:
        color = const Color(0xFFD4AF37);
        label = "PENDING";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withValues(alpha: 0.04),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 44,
                color: Color(0xFFD4AF37),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "No Matching Bookings Found",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              "Try searching with another customer name, phone number, CNIC, or unique booking ID.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
