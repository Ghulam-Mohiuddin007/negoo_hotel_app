import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:negoo_hotel_app/dashboard.dart';
import 'package:negoo_hotel_app/login.dart';
import 'package:negoo_hotel_app/pending.dart';
import 'package:negoo_hotel_app/services/notification_service.dart';

Future<void> main() async {
  // 1. Ensure Flutter engine bindings are fully ready first
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Supabase
  await Supabase.initialize(
    url: 'https://ygtkveocvunfemoznrqx.supabase.co',
    anonKey: 'sb_publishable_lcNZrPe8jt-q8wLa5z_5MQ_R-cqZ8ml',
  );

  // 2. Initialize Pure Supabase Realtime Notification Service
  try {
    await NotificationService().initialize();
    debugPrint("?? Hotel Supabase Notification Service Initialized");
  } catch (e) {
    debugPrint("? Hotel Notification Init Error: ");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final supabaseClient = Supabase.instance.client;
    final Session? activeSession = supabaseClient.auth.currentSession;

    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Negoo Partner Console',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: const Color(0xFFD4AF37),
      ),
      // Direct session presence verification gate
      home: activeSession == null
          ? const HotelLoginScreen()
          : FutureBuilder<Map<String, dynamic>?>(
              future: supabaseClient
                  .from('hotels')
                  .select('is_approved, hotel_name, name')
                  .eq('id', activeSession.user.id)
                  .maybeSingle(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  );
                }

                final record = snapshot.data;
                if (record != null) {
                  final bool isApproved = record['is_approved'] ?? false;
                  final String name =
                      record['hotel_name'] ?? record['name'] ?? 'Partner';

                  if (isApproved) {
                    return const HotelDashboardScreen();
                  } else {
                    return HotelPendingScreen(
                      userId: activeSession.user.id,
                      hotelName: name,
                    );
                  }
                }

                // Fallback if profile data row lookup fails
                return const HotelLoginScreen();
              },
            ),
      routes: {
        '/login': (context) => const HotelLoginScreen(),
        '/hotel_main_dashboard': (context) => const HotelDashboardScreen(),
      },
    );
  }
}
