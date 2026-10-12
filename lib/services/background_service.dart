import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _supabaseUrl = 'https://ygtkveocvunfemoznrqx.supabase.co';
const String _supabaseAnonKey = 'sb_publishable_lcNZrPe8jt-q8wLa5z_5MQ_R-cqZ8ml';

const String notificationChannelId = 'negoo_hotel_bids';
const int notificationId = 888;

class NegooBackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  /// Initialize the background monitoring service
  static Future<void> initialize() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      notificationChannelId,
      'Negoo Live Bids & Bookings',
      description: 'Real-time background notifications for live bids and incoming bookings',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true, // Guarantees Android keeps monitoring bids and bookings even when app is closed
        notificationChannelId: notificationChannelId,
        initialNotificationTitle: 'Negoo Partner Service',
        initialNotificationContent: 'Monitoring live guest bids & bookings',
        foregroundServiceNotificationId: notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// Store the active hotel ID so background isolate can query bids and bookings
  static Future<void> setHotelId(String hotelId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_hotel_id', hotelId);
    _service.invoke('setHotelId', {'hotel_id': hotelId});
  }

  /// Clear the active hotel ID on sign out
  static Future<void> clearHotelId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_hotel_id');
    _service.invoke('clearHotelId');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'Negoo Partner Service',
      content: 'Monitoring live guest bids & bookings',
    );
  }

  // Initialize Local Notifications inside the background isolate
  final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );
  await localNotifications.initialize(
    settings: initializationSettings,
  );

  // Initialize Supabase client in background isolate if not already initialized
  SupabaseClient? client;
  try {
    if (!Supabase.instance.isInitialized) {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseAnonKey,
      );
    }
    client = Supabase.instance.client;
  } catch (e) {
    try {
      client = SupabaseClient(_supabaseUrl, _supabaseAnonKey);
    } catch (_) {}
  }

  final prefs = await SharedPreferences.getInstance();
  String? activeHotelId = prefs.getString('active_hotel_id');

  // Cache notified bid IDs and booking IDs to avoid duplicate alerts
  final Set<String> notifiedBids = {};
  final Set<String> notifiedBookings = {};

  service.on('setHotelId').listen((event) {
    if (event != null && event['hotel_id'] != null) {
      activeHotelId = event['hotel_id'].toString();
    }
  });

  service.on('clearHotelId').listen((_) {
    activeHotelId = null;
    notifiedBids.clear();
    notifiedBookings.clear();
  });

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // Background polling loop every 12 seconds
  Timer.periodic(const Duration(seconds: 12), (timer) async {
    final activeClient = client;
    if (activeHotelId == null || activeHotelId!.isEmpty || activeClient == null) {
      final updatedHotelId = (await SharedPreferences.getInstance()).getString('active_hotel_id');
      if (updatedHotelId != null && updatedHotelId.isNotEmpty) {
        activeHotelId = updatedHotelId;
      } else {
        return;
      }
    }

    if (activeClient == null) return;

    try {
      // 1. Check for incoming live bids targeting this hotel
      final bidsResponse = await activeClient
          .from('bids')
          .select('id, bid_amount, room_id, user_id, expires_at, created_at')
          .eq('hotel_id', activeHotelId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(5);

      final List bidsList = bidsResponse as List;
      for (var bid in bidsList) {
        final String bidId = bid['id'].toString();
        if (!notifiedBids.contains(bidId)) {
          notifiedBids.add(bidId);

          final amount = bid['bid_amount']?.toString() ?? 'N/A';
          await _showSystemNotification(
            notifications: localNotifications,
            id: bidId.hashCode,
            title: "⚡ New Live Pitch Received! (PKR $amount)",
            body: "A guest just placed a live offer of PKR $amount. Review & confirm immediately!",
            payload: 'bid_$bidId',
          );
        }
      }

      // 2. Check for incoming reservations targeting this hotel
      final bookingsResponse = await activeClient
          .from('bookings')
          .select('id, full_name, total_price, status, rooms!fk_room(hotel_id)')
          .eq('rooms.hotel_id', activeHotelId!)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(5);

      final List bookingsList = bookingsResponse as List;
      for (var booking in bookingsList) {
        final String bookingId = booking['id'].toString();
        if (!notifiedBookings.contains(bookingId)) {
          notifiedBookings.add(bookingId);

          final guest = booking['full_name'] ?? 'Guest';
          final price = booking['total_price'] ?? '0';
          await _showSystemNotification(
            notifications: localNotifications,
            id: bookingId.hashCode,
            title: "🏨 New Booking Arrived! (PKR $price)",
            body: "$guest placed a reservation. Open Negoo Partner console to confirm access!",
            payload: 'booking_$bookingId',
          );
        }
      }
    } catch (e) {
      debugPrint("Background monitoring tick error (handled): $e");
    }
  });
}

Future<void> _showSystemNotification({
  required FlutterLocalNotificationsPlugin notifications,
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    notificationChannelId,
    'Negoo Live Bids & Bookings',
    channelDescription: 'Real-time background notifications for live bids and incoming bookings',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    styleInformation: BigTextStyleInformation(''),
  );

  const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const NotificationDetails notificationDetails = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await notifications.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: notificationDetails,
    payload: payload,
  );
}
