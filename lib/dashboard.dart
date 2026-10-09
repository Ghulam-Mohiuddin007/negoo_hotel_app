import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/financials_tab.dart';
import 'package:negoo_hotel_app/live_bids_tab.dart';
import 'package:negoo_hotel_app/rooms_tab.dart';
import 'package:negoo_hotel_app/services/notification_service.dart'; // 💡 Use local service wrapper
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

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    final User? sessionUser = _supabase.auth.currentUser;
    if (sessionUser != null) {
      _currentUserId = sessionUser.id;
    }
    _fetchHotelDetails();
  }

  /// 💡 Connects this physical device back to the Cloud Webhook routing channel
  void _setupFCMNotifications() async {
    if (_currentUserId.isEmpty) return;
    await NotificationService().subscribeToHotelTopic(_currentUserId);
  }

  Future<void> _hotelLogout() async {
    try {
      // 💡 Unsubscribe from the topic on sign out so they stop getting background notifications
      if (_currentUserId.isNotEmpty) {
        await NotificationService().unsubscribeFromHotelTopic(_currentUserId);
      }
    } catch (e) {
      debugPrint("FCM Unsubscribe warning: $e");
    }

    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _fetchHotelDetails() async {
    try {
      if (_currentUserId.isNotEmpty) {
        final data = await _supabase
            .from('hotels')
            .select('hotel_name, name')
            .eq('id', _currentUserId)
            .maybeSingle();

        if (data != null && mounted) {
          setState(() {
            _hotelName = data['hotel_name'] ?? data['name'] ?? "Negoo Venue";
          });
          
          // 💡 Fire subscription sequence now that metadata retrieval is complete
          _setupFCMNotifications();
        }
      }
    } catch (e) {
      debugPrint("Metadata parsing error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _tabViews = [
      HotelIncomingBidsScreen(currentHotelId: _currentUserId),
      FinancialsTabScreen(userId: _currentUserId),
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
              style: const TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const Text(
              "Partner Live Workspace",
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
      body: IndexedStack(index: _currentTabIndex, children: _tabViews),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) => setState(() => _currentTabIndex = index),
        backgroundColor: const Color(0xFF121214),
        selectedItemColor: const Color(0xFFD4AF37),
        unselectedItemColor: Colors.white24,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.gavel_outlined),
            activeIcon: Icon(Icons.gavel),
            label: "Live Bids",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: "Financials",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bed_outlined),
            activeIcon: Icon(Icons.bed),
            label: "Rooms",
          ),
        ],
      ),
    );
  }
}