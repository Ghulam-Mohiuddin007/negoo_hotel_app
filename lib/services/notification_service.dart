import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    debugPrint("🔔 Hotel Supabase Realtime Notification Service Initialized");
  }

  /// Subscribe to hotel-specific channel and database changes
  Future<void> subscribeToHotelTopic(String hotelId) async {
    try {
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
          _showInAppNotification(title: title, body: body, payload: payload);
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
          _showInAppNotification(
            title: "New Live Pitch! ⚡",
            body: "A guest offered PKR $amount for a room reservation.",
            payload: newRecord,
          );
        },
      );

      // 3. Listen for Postgres inserts on notifications table if present
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'hotel_id',
          value: hotelId,
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          final title = newRecord['title']?.toString() ?? "Hotel Notification";
          final body = newRecord['body']?.toString() ?? "";
          _showInAppNotification(title: title, body: body, payload: newRecord);
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

  /// Displays a premium custom in-app notification SnackBar
  void _showInAppNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) {
    HapticFeedback.heavyImpact();

    const Color accentColor = Color(0xFFD4AF37); // Gold
    const IconData icon = Icons.gavel_rounded;

    final snackBar = SnackBar(
      elevation: 6,
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF121214),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      duration: const Duration(seconds: 8),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    rootScaffoldMessengerKey.currentState?.showSnackBar(snackBar);
  }
}
