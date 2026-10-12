import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:negoo_hotel_app/customer_bookings_screen.dart';
import 'package:negoo_hotel_app/live_bids_tab.dart';
import 'package:negoo_hotel_app/negoo_payments_screen.dart';
import 'package:negoo_hotel_app/rooms_tab.dart';
import 'package:negoo_hotel_app/services/database_service.dart';
import 'package:negoo_hotel_app/services/notification_service.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotelDashboardScreen extends StatefulWidget {
  const HotelDashboardScreen({super.key});

  @override
  State<HotelDashboardScreen> createState() => _HotelDashboardScreenState();
}

class _HotelDashboardScreenState extends State<HotelDashboardScreen> {
  int _currentTabIndex = 0;
  late final SupabaseClient _supabase;
  String _hotelName = "Loading Venue...";
  String _currentUserId = "";
  RealtimeChannel? _dashboardBookingsChannel;
  int _pendingBookingsCount = 0;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    final User? sessionUser = _supabase.auth.currentUser;
    if (sessionUser != null) {
      _currentUserId = sessionUser.id;
    }
    _fetchHotelDetails();
    _checkPendingBookings();
    _subscribeToDashboardBookings();
  }

  @override
  void dispose() {
    if (_dashboardBookingsChannel != null) {
      _supabase.removeChannel(_dashboardBookingsChannel!);
    }
    super.dispose();
  }

  void _subscribeToDashboardBookings() {
    if (_currentUserId.isEmpty) return;
    try {
      _dashboardBookingsChannel = _supabase
          .channel('dashboard_bookings_monitor_$_currentUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (payload) {
              if (payload.eventType == PostgresChangeEvent.insert) {
                HapticFeedback.heavyImpact();
                ToastService.info("⚡ New Guest Booking! Tap 'Bookings' to confirm immediately.");
              }
              _checkPendingBookings();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  Future<void> _checkPendingBookings() async {
    if (_currentUserId.isEmpty) return;
    try {
      final list = await DatabaseService().fetchHotelBookings(_currentUserId);
      final count = list.where((b) => b['status'] == 'pending').length;
      if (mounted) {
        setState(() => _pendingBookingsCount = count);
      }
    } catch (_) {}
  }

  void _setupNotifications() async {
    if (_currentUserId.isEmpty) return;
    await NotificationService().subscribeToHotelTopic(_currentUserId);
  }

  Future<void> _hotelLogout() async {
    try {
      if (_currentUserId.isNotEmpty) {
        await NotificationService().unsubscribeFromHotelTopic(_currentUserId);
      }
    } catch (e) {
      debugPrint("Unsubscribe warning: $e");
    }

    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _fetchHotelDetails() async {
    if (_currentUserId.isEmpty) return;

    // Instant 0ms read from Redis Cache
    final cached = RedisCacheService().getCachedHotelProfile(_currentUserId);
    if (cached != null && mounted) {
      setState(() {
        _hotelName = cached['hotel_name'] ?? cached['name'] ?? "Negoo Venue";
      });
      _setupNotifications();
    }

    try {
      final data = await _supabase
          .from('hotels')
          .select('hotel_name, name, is_approved')
          .eq('id', _currentUserId)
          .maybeSingle();

      if (data != null && mounted) {
        await RedisCacheService().cacheHotelProfile(_currentUserId, data);
        setState(() {
          _hotelName = data['hotel_name'] ?? data['name'] ?? "Negoo Venue";
        });
        
        _setupNotifications();
      }
    } catch (e) {
      debugPrint("Metadata parsing error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabViews = [
      HotelIncomingBidsScreen(currentHotelId: _currentUserId),
      CustomerBookingsScreen(userId: _currentUserId),
      NegooPaymentsScreen(userId: _currentUserId),
      RoomsTabScreen(userId: _currentUserId),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121214),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _hotelName.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const Text(
              "Partner Live Workspace",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.white38,
              size: 20,
            ),
            tooltip: "Secure Sign Out",
            onPressed: _hotelLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _currentTabIndex, children: tabViews),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) {
          setState(() => _currentTabIndex = index);
          if (index == 1) {
            _checkPendingBookings();
          }
        },
        backgroundColor: const Color(0xFF121214),
        selectedItemColor: const Color(0xFFD4AF37),
        unselectedItemColor: Colors.white24,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.gavel_outlined),
            activeIcon: Icon(Icons.gavel),
            label: "Live Bids",
          ),
          BottomNavigationBarItem(
            icon: _pendingBookingsCount > 0
                ? Badge(
                    label: Text("$_pendingBookingsCount"),
                    backgroundColor: const Color(0xFFD4AF37),
                    textColor: Colors.black,
                    child: const Icon(Icons.confirmation_number_outlined),
                  )
                : const Icon(Icons.confirmation_number_outlined),
            activeIcon: const Icon(Icons.confirmation_number),
            label: "Bookings",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: "Negoo Pay",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.bed_outlined),
            activeIcon: Icon(Icons.bed),
            label: "Rooms",
          ),
        ],
      ),
    );
  }
}