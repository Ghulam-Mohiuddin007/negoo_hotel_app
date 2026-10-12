import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotelPendingScreen extends StatelessWidget {
  final String userId;
  final String hotelName;

  const HotelPendingScreen({
    super.key,
    required this.userId,
    required this.hotelName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          // Listen live to the specific hotel record matching this owner ID
          stream: Supabase.instance.client
              .from('hotels')
              .stream(primaryKey: ['id'])
              .eq('id', userId),
          builder: (context, snapshot) {
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              final hotelData = snapshot.data!.first;
              final bool approved = hotelData['is_approved'] ?? false;

              // Immediate hot-swap redirection to Core Dashboard upon admin approval activation
              if (approved) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  Navigator.pushReplacementNamed(
                    context,
                    '/hotel_main_dashboard',
                  );
                });
              }
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Dynamic Pulsing Glassmorphic Radar Container Loop
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFD4AF37).withValues(alpha: 0.03),
                          ),
                        ),
                        const Icon(
                          Icons.shield_moon_outlined,
                          size: 54,
                          color: Color(0xFFD4AF37),
                        ),
                      ],
                    ),
                    const SizedBox(height: 35),
                    const Text(
                      "APPLICATION PENDING",
                      style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hotelName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.white.withValues(alpha: 0.01),
                        child: Text(
                          "Your property compliance files are currently being audited by the Negoo Operations Panel. The console dashboard features will automatically unlock the second authentication logs clear.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
