import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/dashboard.dart';
import 'package:negoo_hotel_app/login.dart';
import 'package:negoo_hotel_app/splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // 1. Ensure Flutter engine bindings are fully ready first
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Initialize Supabase client
  await Supabase.initialize(
    url: 'https://ygtkveocvunfemoznrqx.supabase.co',
    publishableKey: 'sb_publishable_lcNZrPe8jt-q8wLa5z_5MQ_R-cqZ8ml',
  );

  // 3. Launch App immediately (HotelSplashScreen handles luxury branding & session routing)
  runApp(const MyApp());
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'Negoo Partner Console',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        primaryColor: const Color(0xFFD4AF37),
      ),
      // Displays luxury splash screen directly without Flutter logo
      home: const HotelSplashScreen(),
      routes: {
        '/splash': (context) => const HotelSplashScreen(),
        '/login': (context) => const HotelLoginScreen(),
        '/hotel_main_dashboard': (context) => const HotelDashboardScreen(),
      },
    );
  }
}
