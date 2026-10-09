import 'dart:async';
import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/login.dart';

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

  @override
  void initState() {
    super.initState();

    // 1. Initialize the Animation Controller (2-second total duration)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // 2. Scale Animation for the branding icon (0.0 to 1.0 with a smooth easeOutBack curve)
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.60, curve: Curves.easeOutBack),
      ),
    );

    // 3. Fade Animation for the text labels (Starts halfway through the icon animation)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.40, 1.0, curve: Curves.easeIn),
      ),
    );

    // 4. Start the animation engine
    _animationController.forward();

    // 5. Navigate to the Hotel Login screen after the animation completes
    Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const HotelLoginScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFF0A0A0A,
      ), // Deep Obsidian matching the auth workflow
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
                      color: Colors.white.withOpacity(0.01),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withOpacity(0.1),
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
                          fontWeight:
                              FontWeight.w200, // Minimalist fine typography
                          letterSpacing: 8.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "PARTNER SYSTEM",
                        style: TextStyle(
                          color: const Color(0xFFD4AF37).withOpacity(0.7),
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
          color: const Color(0xFFD4AF37).withOpacity(0.02),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4AF37).withOpacity(0.03),
              blurRadius: 100,
              spreadRadius: 50,
            ),
          ],
        ),
      ),
    );
  }
}
