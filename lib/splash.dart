import 'dart:async';
import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/dashboard.dart';
import 'package:negoo_hotel_app/login.dart';
import 'package:negoo_hotel_app/pending.dart';
import 'package:negoo_hotel_app/services/notification_service.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:negoo_hotel_app/verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotelSplashScreen extends StatefulWidget {
  const HotelSplashScreen({super.key});

  @override
  State<HotelSplashScreen> createState() => _HotelSplashScreenState();
}

class _HotelSplashScreenState extends State<HotelSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  Widget? _targetDestination;
  bool _animationCompleted = false;

  @override
  void initState() {
    super.initState();

    // 1. Initialize the Animation Controller (1.6-second smooth duration)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // 2. Scale Animation for branding icon (smooth easeOutBack)
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    // 3. Fade Animation for luxury typography
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.35, 1.0, curve: Curves.easeIn),
      ),
    );

    _animationController.forward().then((_) {
      _animationCompleted = true;
      _attemptNavigation();
    });

    // 4. Resolve session and permissions in parallel with animation
    _resolveSessionAndWarmup();
  }

  Future<void> _resolveSessionAndWarmup() async {
    try {
      // Warm up Redis Cache engine
      await RedisCacheService().warmup();

      // Initialize NotificationService non-blockingly
      NotificationService().initialize().catchError((e) {
        debugPrint("Notification non-blocking init note: $e");
      });

      final supabase = Supabase.instance.client;
      final Session? activeSession = supabase.auth.currentSession;

      if (activeSession == null) {
        _targetDestination = const HotelLoginScreen();
      } else {
        final userId = activeSession.user.id;

        // Check Redis cache for instant 0ms hotel profile read
        final cachedProfile = RedisCacheService().getCachedHotelProfile(userId);
        if (cachedProfile != null) {
          final isApproved = cachedProfile['is_approved'] ?? false;
          final hotelName = cachedProfile['hotel_name'] ?? cachedProfile['name'] ?? 'Partner';
          if (isApproved) {
            _targetDestination = const HotelDashboardScreen();
          } else {
            _targetDestination = HotelPendingScreen(userId: userId, hotelName: hotelName);
          }
        } else {
          // Query Supabase for latest approval state
          final record = await supabase
              .from('hotels')
              .select('is_approved, hotel_name, name, owner_cnic_url')
              .eq('id', userId)
              .maybeSingle();

          if (record != null) {
            await RedisCacheService().cacheHotelProfile(userId, record);
            final bool isApproved = record['is_approved'] ?? false;
            final String name = record['hotel_name'] ?? record['name'] ?? 'Partner';
            final String? cnicUrl = record['owner_cnic_url'];

            if (isApproved) {
              _targetDestination = const HotelDashboardScreen();
            } else if (cnicUrl != null && cnicUrl.isNotEmpty) {
              _targetDestination = HotelPendingScreen(userId: userId, hotelName: name);
            } else {
              _targetDestination = HotelVerificationScreen(userId: userId, hotelName: name);
            }
          } else {
            _targetDestination = const HotelLoginScreen();
          }
        }
      }
    } catch (e) {
      debugPrint("Splash session resolution fallback: $e");
      _targetDestination = const HotelLoginScreen();
    }

    if (_animationCompleted) {
      _attemptNavigation();
    }
  }

  void _attemptNavigation() {
    if (!mounted || _targetDestination == null) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _targetDestination!,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A), // Deep Obsidian
      body: Stack(
        children: [
          _buildBackgroundSubtleGlow(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Luxury Icon
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.01),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
                      ),
                    ),
                    child: const Icon(
                      Icons.hotel_class_rounded,
                      size: 80,
                      color: Color(0xFFD4AF37), // Champagne Gold
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Animated Text Labels
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      const Text(
                        "N E G O O",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w200,
                          letterSpacing: 8.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "PARTNER SYSTEM",
                        style: TextStyle(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.7),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tiny minimalist footer branding
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: const Text(
                "LUXURY ECOSYSTEM V2.0",
                style: TextStyle(
                  color: Colors.white12,
                  fontSize: 10,
                  letterSpacing: 2.0,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundSubtleGlow() {
    return Center(
      child: Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFD4AF37).withValues(alpha: 0.02),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.03),
              blurRadius: 100,
              spreadRadius: 50,
            ),
          ],
        ),
      ),
    );
  }
}
