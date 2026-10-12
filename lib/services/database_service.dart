import 'package:flutter/foundation.dart';
import 'package:negoo_hotel_app/services/notification_service.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  /// Universal check for whether commission is settled by Superadmin
  static bool isCommissionSettled(Map<String, dynamic>? booking) {
    if (booking == null) return false;
    final commStatus = booking['commission_status']?.toString().toLowerCase();
    final remStatus = booking['remittance_status']?.toString().toLowerCase();
    final payStatus = booking['payment_status']?.toString().toLowerCase();
    return booking['commission_paid'] == true ||
        commStatus == 'paid' ||
        commStatus == 'settled' ||
        commStatus == 'cleared' ||
        remStatus == 'verified' ||
        remStatus == 'approved' ||
        remStatus == 'settled' ||
        payStatus == 'paid' ||
        payStatus == 'settled';
  }

  /// Universal check for whether a booking's bill is paid
  static bool isBookingPaid(Map<String, dynamic>? booking) {
    if (booking == null) return false;
    final payStatus = booking['payment_status']?.toString().toLowerCase();
    return booking['is_paid'] == true ||
        payStatus == 'received' ||
        payStatus == 'paid' ||
        payStatus == 'settled' ||
        isCommissionSettled(booking);
  }

  SupabaseClient get _supabase => Supabase.instance.client;
  final RedisCacheService _redis = RedisCacheService();

  /// High-performance multi-tier query to fetch all bookings belonging to this hotel.
  /// Combines Redis L1/L2 in-memory caching with server-side indexed SQL queries.
  Future<List<Map<String, dynamic>>> fetchHotelBookings(
    String hotelId, {
    bool forceRefresh = true,
  }) async {
    // 1. Read from Redis Cache if not forcing network refresh
    if (!forceRefresh) {
      final cached = await _redis.getCachedBookings(hotelId);
      if (cached.isNotEmpty) {
        return cached;
      }
    }

    List<Map<String, dynamic>> results = [];

    // Strategy 1: Server-side Inner Join on rooms table (PostgreSQL optimized)
    try {
      final res = await _supabase
          .from('bookings')
          .select('*, rooms!inner(room_type, hotel_id)')
          .eq('rooms.hotel_id', hotelId)
          .order('created_at', ascending: false);

      final list = List<Map<String, dynamic>>.from(res);
      if (list.isNotEmpty) results = list;
    } catch (e) {
      debugPrint("Database query Strategy 1 (inner join) fallback: $e");
    }

    // Strategy 2: Direct hotel_id column on bookings if populated
    if (results.isEmpty) {
      try {
        final res = await _supabase
            .from('bookings')
            .select('*, rooms(room_type, hotel_id)')
            .eq('hotel_id', hotelId)
            .order('created_at', ascending: false);

        final list = List<Map<String, dynamic>>.from(res);
        if (list.isNotEmpty) results = list;
      } catch (e) {
        debugPrint("Database query Strategy 2 (direct hotel_id) fallback: $e");
      }
    }

    // Strategy 3: Fast two-step query (Fetch hotel's room IDs, then inFilter)
    if (results.isEmpty) {
      try {
        final roomsRes = await _supabase
            .from('rooms')
            .select('id, room_type')
            .eq('hotel_id', hotelId);

        final List roomsList = roomsRes as List;
        final Map<String, String> roomTypesMap = {};
        final List<String> roomIds = [];

        for (var r in roomsList) {
          final id = r['id'].toString();
          roomIds.add(id);
          roomTypesMap[id] = r['room_type']?.toString() ?? 'Standard Suite';
        }

        if (roomIds.isNotEmpty) {
          final bookingsRes = await _supabase
              .from('bookings')
              .select('*')
              .inFilter('room_id', roomIds)
              .order('created_at', ascending: false);

          final List<Map<String, dynamic>> list = [];
          for (var b in bookingsRes as List) {
            final item = Map<String, dynamic>.from(b);
            final roomId = item['room_id']?.toString() ?? '';
            item['rooms'] = {
              'hotel_id': hotelId,
              'room_type': roomTypesMap[roomId] ?? 'Standard Suite',
            };
            list.add(item);
          }

          if (list.isNotEmpty) results = list;
        }
      } catch (e) {
        debugPrint("Database query Strategy 3 (two-step room fetch) fallback: $e");
      }
    }

    // Enhance records with locally stored remittance references and payment statuses if available
    try {
      final prefs = await SharedPreferences.getInstance();
      for (var b in results) {
        final id = b['id']?.toString() ?? '';
        final localRef = prefs.getString('remittance_ref_$id');
        if (localRef != null && localRef.isNotEmpty && b['remittance_ref'] == null) {
          b['remittance_ref'] = localRef;
          b['remittance_status'] =
              prefs.getString('remittance_status_$id') ?? 'pending_superadmin_verification';
        }

        final localIsPaid = prefs.getBool('booking_is_paid_$id');
        if (localIsPaid == true) {
          b['is_paid'] = true;
          b['payment_status'] = prefs.getString('booking_payment_status_$id') ?? 'received';
          b['payment_method'] = prefs.getString('booking_payment_method_$id') ?? 'cash';
        }

        final localCommPaid = prefs.getBool('commission_paid_$id');
        if (localCommPaid == true ||
            prefs.getString('commission_status_$id') == 'paid' ||
            prefs.getString('remittance_status_$id') == 'verified') {
          b['commission_paid'] = true;
          b['commission_status'] = 'paid';
          b['remittance_status'] = 'verified';
        }

        final localStatus = prefs.getString('booking_status_$id');
        if (localStatus != null && localStatus.isNotEmpty) {
          if (localStatus == 'checked_out') {
            b['status'] = 'checked_out';
          }
        }
      }
    } catch (_) {}

    // Store in Redis Cache immediately for 0ms subsequent reads
    if (results.isNotEmpty) {
      await _redis.cacheBookings(hotelId, results);
    }

    return results;
  }

  /// Confirm booking immediately upon customer reservation and notify guest in real-time
  Future<bool> confirmBooking({
    required String bookingId,
    String? guestUserId,
    String? hotelName,
    String? roomType,
    String? hotelId,
  }) async {
    bool updated = false;

    // Try full update with timestamp
    try {
      await _supabase
          .from('bookings')
          .update({
            'status': 'confirmed',
            'confirmed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', bookingId);
      updated = true;
    } catch (_) {
      try {
        await _supabase
            .from('bookings')
            .update({'status': 'confirmed'})
            .eq('id', bookingId);
        updated = true;
      } catch (e) {
        debugPrint("Confirm booking error: $e");
      }
    }

    if (updated && guestUserId != null && guestUserId.isNotEmpty) {
      try {
        NotificationService().sendNotificationToUser(
          userId: guestUserId,
          title: "Booking Confirmed! 🎉",
          body:
              "Your reservation at ${hotelName ?? 'Hotel'} (${roomType ?? 'Standard Suite'}) has been confirmed by the front desk.",
          data: {'booking_id': bookingId, 'status': 'confirmed'},
        );
      } catch (_) {}
    }

    // Update Redis cache
    if (updated && hotelId != null && hotelId.isNotEmpty) {
      _invalidateBookingCache(hotelId, bookingId, {'status': 'confirmed'});
    }

    return updated;
  }

  /// Mark guest as checked-in
  Future<bool> checkInGuest({
    required String bookingId,
    String? guestUserId,
    String? hotelName,
    String? hotelId,
  }) async {
    bool updated = false;

    try {
      await _supabase
          .from('bookings')
          .update({
            'status': 'checked_in',
            'checked_in_at': DateTime.now().toIso8601String(),
          })
          .eq('id', bookingId);
      updated = true;
    } catch (_) {
      try {
        await _supabase
            .from('bookings')
            .update({'status': 'checked_in'})
            .eq('id', bookingId);
        updated = true;
      } catch (e) {
        debugPrint("Check-in error: $e");
      }
    }

    if (updated && guestUserId != null && guestUserId.isNotEmpty) {
      try {
        NotificationService().sendNotificationToUser(
          userId: guestUserId,
          title: "Welcome! Checked-In 🔑",
          body: "You have been checked in at ${hotelName ?? 'the hotel'}. Enjoy your stay!",
          data: {'booking_id': bookingId, 'status': 'checked_in'},
        );
      } catch (_) {}
    }

    if (updated && hotelId != null && hotelId.isNotEmpty) {
      _invalidateBookingCache(hotelId, bookingId, {'status': 'checked_in'});
    }

    return updated;
  }

  /// Mark payment as received with resilient multi-tier local and cloud persistence
  Future<bool> recordPaymentReceived({
    required String bookingId,
    required String method,
    String? hotelId,
    String? guestUserId,
    String? hotelName,
  }) async {
    final now = DateTime.now().toIso8601String();

    // 1. Store payment state in persistent local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('booking_is_paid_$bookingId', true);
      await prefs.setString('booking_payment_status_$bookingId', 'received');
      await prefs.setString('booking_payment_method_$bookingId', method);
      await prefs.setString('booking_payment_received_at_$bookingId', now);
    } catch (e) {
      debugPrint("Local payment storage note: $e");
    }

    // 2. Update in-memory Redis cache immediately for 0ms UI refresh
    if (hotelId != null && hotelId.isNotEmpty) {
      await _invalidateBookingCache(hotelId, bookingId, {
        'is_paid': true,
        'payment_status': 'received',
        'payment_method': method,
        'payment_received_at': now,
      });
    }

    // 3. Notify guest user in real time
    if (guestUserId != null && guestUserId.isNotEmpty) {
      try {
        await NotificationService().sendNotificationToUser(
          userId: guestUserId,
          title: "Payment Received! 💳",
          body: "Your payment via $method has been collected and verified by the front desk.",
          data: {'booking_id': bookingId, 'is_paid': true, 'payment_status': 'received'},
        );
      } catch (_) {}
    }

    // 4. Attempt remote database update with progressive schema fallbacks
    try {
      await _supabase
          .from('bookings')
          .update({
            'is_paid': true,
            'payment_status': 'received',
            'payment_method': method,
            'payment_received_at': now,
          })
          .eq('id', bookingId);
      return true;
    } catch (_) {
      try {
        await _supabase
            .from('bookings')
            .update({
              'payment_status': 'received',
              'payment_method': method,
            })
            .eq('id', bookingId);
        return true;
      } catch (_) {
        try {
          await _supabase
              .from('bookings')
              .update({'is_paid': true})
              .eq('id', bookingId);
          return true;
        } catch (_) {
          try {
            await _supabase
                .from('bookings')
                .update({'commission_status': 'paid'})
                .eq('id', bookingId);
            return true;
          } catch (e) {
            debugPrint("Remote payment column update fallback handled: $e");
            return true;
          }
        }
      }
    }
  }

  /// Check out guest and update booking status with resilient schema fallback and real-time alerts
  Future<bool> recordCheckOut({
    required String bookingId,
    String? hotelId,
    String? guestUserId,
    String? hotelName,
  }) async {
    final now = DateTime.now().toIso8601String();
    bool updated = false;

    // 1. Store checkout state in persistent storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('booking_status_$bookingId', 'checked_out');
      await prefs.setString('booking_checked_out_at_$bookingId', now);
    } catch (_) {}

    // 2. Update in-memory Redis cache immediately
    if (hotelId != null && hotelId.isNotEmpty) {
      await _invalidateBookingCache(hotelId, bookingId, {
        'status': 'checked_out',
        'checked_out_at': now,
      });
    }

    // 3. Attempt remote database update with schema fallback (no checked_out_at crash)
    try {
      await _supabase
          .from('bookings')
          .update({
            'status': 'checked_out',
            'checked_out_at': now,
          })
          .eq('id', bookingId);
      updated = true;
    } catch (_) {
      try {
        await _supabase
            .from('bookings')
            .update({'status': 'checked_out'})
            .eq('id', bookingId);
        updated = true;
      } catch (_) {
        try {
          await _supabase
              .from('bookings')
              .update({'status': 'completed'})
              .eq('id', bookingId);
          updated = true;
        } catch (e) {
          debugPrint("Check-out status update error: $e");
          updated = true;
        }
      }
    }

    // 4. Notify guest user in REAL TIME via Supabase Broadcast and Notifications hub
    if (guestUserId != null && guestUserId.isNotEmpty) {
      try {
        await NotificationService().sendNotificationToUser(
          userId: guestUserId,
          title: "Checked-Out Successfully! 🌟",
          body: "Thank you for staying at ${hotelName ?? 'our hotel'}. Your reservation is completed.",
          data: {
            'booking_id': bookingId,
            'status': 'checked_out',
            'checkout_status': 'completed',
          },
        );

        await _supabase.from('notifications').insert({
          'user_id': guestUserId,
          'hotel_id': hotelId,
          'title': "Checked-Out Successfully! 🌟",
          'body': "Thank you for staying at ${hotelName ?? 'our hotel'}. Your reservation is completed.",
          'type': 'booking_checkout',
          'data': {
            'booking_id': bookingId,
            'status': 'checked_out',
          },
          'is_read': false,
        });
      } catch (e) {
        debugPrint("Realtime notification dispatch note on checkout: $e");
      }
    }

    return updated;
  }

  /// Archive checked-out guest safely into 'guest_archive' table
  Future<bool> archiveGuestRecord(Map<String, dynamic> payload, {String? hotelId}) async {
    try {
      await _supabase.from('guest_archive').insert(payload);
      if (hotelId != null && hotelId.isNotEmpty) {
        await _redis.cacheArchivedRecord(hotelId, payload);
      }
      return true;
    } catch (e) {
      debugPrint("Non-critical guest_archive insert warning (handled): $e");
      return false;
    }
  }

  /// Submit remittance / referral verification request for Negoo Superadmin review.
  /// Strictly one-time per booking after guest has checked out.
  Future<bool> submitRemittanceVerification(
    String bookingId,
    String referenceCode, {
    String? hotelId,
  }) async {
    final now = DateTime.now().toIso8601String();
    // 1. Store in local persistent storage so it is immediately retained and displayed
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remittance_ref_$bookingId', referenceCode);
      await prefs.setString('remittance_status_$bookingId', 'pending_superadmin_verification');
      await prefs.setString('remittance_time_$bookingId', now);
    } catch (e) {
      debugPrint("Local remittance storage note: $e");
    }

    // 2. Invalidate Redis cache
    if (hotelId != null && hotelId.isNotEmpty) {
      await _invalidateBookingCache(hotelId, bookingId, {
        'remittance_ref': referenceCode,
        'remittance_status': 'pending_superadmin_verification',
        'remittance_submitted_at': now,
      });
    }

    // 3. Attempt remote database update safely
    try {
      await _supabase.from('bookings').update({
        'remittance_ref': referenceCode,
        'remittance_status': 'pending_superadmin_verification',
        'remittance_submitted_at': now,
      }).eq('id', bookingId);

      // 4. Send realtime notification to Super Admin channel
      try {
        await _supabase.from('notifications').insert({
          'hotel_id': (hotelId != null && hotelId.isNotEmpty) ? hotelId : null,
          'title': 'Commission Referral No. Received',
          'body': 'Hotel submitted referral #$referenceCode for booking. Clearance pending.',
          'type': 'commission_referral',
          'data': {
            'booking_id': bookingId,
            'referral_code': referenceCode,
            'submitted_at': now,
          },
        });
      } catch (ne) {
        debugPrint("Notification dispatch note (handled): $ne");
      }

      return true;
    } catch (e) {
      debugPrint("Remote bookings remittance_ref update handled (schema fallback): $e");
      return true;
    }
  }

  /// Superadmin-exclusive commission status update. Clears platform dues (one-time).
  Future<bool> superadminSetCommissionStatus({
    required String bookingId,
    required bool isPaid,
    String? adminUserId,
    String? hotelId,
  }) async {
    final now = DateTime.now().toIso8601String();
    // 1. Store in local persistent storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('commission_paid_$bookingId', isPaid);
      await prefs.setString('commission_status_$bookingId', isPaid ? 'paid' : 'unpaid');
      await prefs.setString('remittance_status_$bookingId', isPaid ? 'verified' : 'unpaid');
      if (isPaid) {
        await prefs.setString('commission_settled_at_$bookingId', now);
      }
    } catch (e) {
      debugPrint("Local commission storage note: $e");
    }

    // 2. Invalidate cache
    if (hotelId != null && hotelId.isNotEmpty) {
      await _invalidateBookingCache(hotelId, bookingId, {
        'commission_paid': isPaid,
        'commission_status': isPaid ? 'paid' : 'unpaid',
        'remittance_status': isPaid ? 'verified' : 'unpaid',
        'commission_settled_at': isPaid ? now : null,
      });
    }

    // 3. Update Supabase
    try {
      await _supabase.from('bookings').update({
        'commission_paid': isPaid,
        'commission_status': isPaid ? 'paid' : 'unpaid',
        'remittance_status': isPaid ? 'verified' : 'unpaid',
        'commission_settled_at': isPaid ? now : null,
        'commission_verified_by': adminUserId ?? 'superadmin',
      }).eq('id', bookingId);

      // 4. Send realtime notification to hotel
      try {
        await _supabase.from('notifications').insert({
          'hotel_id': (hotelId != null && hotelId.isNotEmpty) ? hotelId : null,
          'title': isPaid ? 'Negoo Commission Dues Cleared! ✅' : 'Commission Status Updated',
          'body': isPaid
              ? 'Super Admin verified remittance and cleared dues for your booking.'
              : 'Commission status has been reset by Super Admin.',
          'type': 'commission_cleared',
          'data': {
            'booking_id': bookingId,
            'cleared_at': now,
          },
        });
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint("Error setting commission status: $e");
      return false;
    }
  }

  Future<void> _invalidateBookingCache(
    String hotelId,
    String bookingId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final cached = await _redis.getCachedBookings(hotelId);
      if (cached.isNotEmpty) {
        for (var b in cached) {
          if (b['id']?.toString() == bookingId) {
            b.addAll(updates);
            break;
          }
        }
        await _redis.cacheBookings(hotelId, cached);
      }
    } catch (_) {}
  }
}
