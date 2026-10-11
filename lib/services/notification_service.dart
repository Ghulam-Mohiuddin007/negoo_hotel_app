import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:negoo_hotel_app/services/background_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Declare a global key to allow showing SnackBars or routing from the service without context
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

  RealtimeChannel? _hotelChannel;
  bool _isInitialized = false;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    if (_isInitialized) return;

    // 1. Initialize Flutter Local Notifications for OS-level heads-up alerts
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
    );

    // Request permissions on Android 13+
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // 2. Initialize Background Service for notifications when app is closed
    try {
      await NegooBackgroundService.initialize();
      debugPrint("🚀 Negoo Background Service Initialized");
    } catch (e) {
      debugPrint("Background Service Init warning: $e");
    }

    _isInitialized = true;
    debugPrint("🔔 Hotel Supabase Realtime & Background Notification Service Initialized");
  }

  /// Subscribe to hotel-specific channel and database changes
  Future<void> subscribeToHotelTopic(String hotelId) async {
    try {
      // Register active hotel ID with the background service
      await NegooBackgroundService.setHotelId(hotelId);

      if (_hotelChannel != null) {
        await _supabase.removeChannel(_hotelChannel!);
        _hotelChannel = null;
      }

      final channelName = 'hotel_$hotelId';
      final channel = _supabase.channel(channelName);

      // 1. Listen for instant broadcast messages targeted at this hotel
      channel.onBroadcast(
        event: 'notification',
        callback: (payload) {
          debugPrint("📩 Realtime hotel notification received: $payload");
          final title = payload['title']?.toString() ?? "New Live Pitch! ⚡";
          final body = payload['body']?.toString() ?? "";
          _triggerFullNotification(title: title, body: body, payload: payload);
        },
      );

      // 2. Listen for Postgres inserts on bids targeting this hotel
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'bids',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'hotel_id',
          value: hotelId,
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          final amount = newRecord['bid_amount']?.toString() ?? 'N/A';
          _triggerFullNotification(
            title: "New Live Pitch! ⚡",
            body: "A guest offered PKR $amount for a room reservation.",
            payload: newRecord,
          );
        },
      );

      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint("✅ Subscribed to Supabase hotel channel: $channelName");
        } else if (error != null) {
          debugPrint("❌ Realtime subscribe error for hotel channel: $error");
        }
      });

      _hotelChannel = channel;
    } catch (e) {
      debugPrint("❌ Error subscribing to hotel topic via Supabase: $e");
    }
  }

  /// Unsubscribe from hotel-specific channel
  Future<void> unsubscribeFromHotelTopic(String hotelId) async {
    try {
      await NegooBackgroundService.clearHotelId();
      if (_hotelChannel != null) {
        await _supabase.removeChannel(_hotelChannel!);
        _hotelChannel = null;
        debugPrint("🔕 Unsubscribed from Supabase hotel channel: hotel_$hotelId");
      }
    } catch (e) {
      debugPrint("❌ Error unsubscribing from hotel channel: $e");
    }
  }

  /// Dispatch broadcast notification to a specific user channel
  Future<void> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final channelName = 'user_$userId';
      final channel = _supabase.channel(channelName);

      await channel.sendBroadcastMessage(
        event: 'notification',
        payload: {
          'title': title,
          'body': body,
          'timestamp': DateTime.now().toIso8601String(),
          ...?data,
        },
      );
      debugPrint("📡 Broadcast notification dispatched to $channelName: $title");

      // Attempt to persist in notifications table (swallows if table is optional)
      try {
        await _supabase.from('notifications').insert({
          'user_id': userId,
          'title': title,
          'body': body,
          'data': data ?? {},
          'is_read': false,
        });
      } catch (_) {
        // Ignored if notifications table has RLS or does not exist
      }
    } catch (e) {
      debugPrint("❌ Error broadcasting notification to user: $e");
    }
  }

  /// Triggers both in-app SnackBar and OS-level system notification
  void _triggerFullNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) {
    // 1. Show OS system tray notification
    _showOsSystemNotification(title: title, body: body);

    // 2. Show in-app banner
    _showInAppNotification(title: title, body: body, payload: payload);
  }

  Future<void> _showOsSystemNotification({
    required String title,
    required String body,
  }) async {
    try {
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        notificationChannelId,
        'Negoo Live Bids & Bookings',
        channelDescription: 'Real-time notifications for live bids and bookings',
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

      await _localNotifications.show(
        id: DateTime.now().millisecond,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
      );
    } catch (e) {
      debugPrint("OS notification display error: $e");
    }
  }

  /// Displays a premium custom in-app notification SnackBar
  void _showInAppNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) {
    HapticFeedback.heavyImpact();
    ToastService.info("$title\n$body");
  }
}
