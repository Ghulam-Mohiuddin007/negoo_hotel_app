import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/pending.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';
import 'package:negoo_hotel_app/singup.dart';
import 'package:negoo_hotel_app/verification.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotelLoginScreen extends StatefulWidget {
  const HotelLoginScreen({super.key});

  @override
  State<HotelLoginScreen> createState() => _HotelLoginScreenState();
}

class _HotelLoginScreenState extends State<HotelLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // 1. Authenticate credentials against Supabase Auth records
      final AuthResponse response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final String? userId = response.user?.id;

      if (userId != null) {
        // Query hotels table with complete approval & verification metadata
        final hotelRecord = await supabase
            .from('hotels')
            .select('is_approved, hotel_name, name, owner_cnic_url')
            .eq('id', userId)
            .maybeSingle();

        if (!mounted) return;

        if (hotelRecord != null) {
          // Cache in Redis for instant 0ms retrieval on subsequent visits
          await RedisCacheService().cacheHotelProfile(userId, hotelRecord);
          if (!mounted) return;

          final bool isApproved = hotelRecord['is_approved'] ?? false;
          final String verifiedName =
              hotelRecord['hotel_name'] ?? hotelRecord['name'] ?? 'Partner';
          final String? uploadedCnic = hotelRecord['owner_cnic_url'];

          if (isApproved) {
            _showSnackBar("Welcome back, $verifiedName!", Colors.green);
            Navigator.pushReplacementNamed(context, '/hotel_main_dashboard');
          } else if (uploadedCnic != null && uploadedCnic.isNotEmpty) {
            // STATE 2: Completed onboarding docs, awaiting Super Admin approval
            _showSnackBar(
              "Account under review. Tracking approval pipeline...",
              const Color(0xFFD4AF37),
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (c) => HotelPendingScreen(
                  userId: userId,
                  hotelName: verifiedName,
                ),
              ),
            );
          } else {
            // STATE 3: Fresh signup profile or incomplete compliance files
            _showSnackBar(
              "Please complete your identity and compliance profile onboarding.",
              const Color(0xFFD4AF37),
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (c) => HotelVerificationScreen(
                  userId: userId,
                  hotelName: verifiedName,
                ),
              ),
            );
          }
        } else {
          _showSnackBar("No active hotel partner profile found.", Colors.orange);
        }
      }
    } on AuthException catch (e) {
      _showSnackBar(e.message, Colors.redAccent);
    } catch (e) {
      _showSnackBar("Authentication process halted: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    if (color == Colors.redAccent || color == Colors.red) {
      ToastService.error(msg);
    } else if (color == Colors.green) {
      ToastService.success(msg);
    } else {
      ToastService.info(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              _buildLuxuryGlow(constraints),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildBrandHeader(),
                          const SizedBox(height: 40),
                          _buildGlassCard(),
                          const SizedBox(height: 32),
                          _buildSubmitButton(),
                          const SizedBox(height: 24),
                          _buildSignupLink(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF141418),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.hotel_class_rounded,
            size: 42,
            color: Color(0xFFD4AF37),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Partner Console",
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Manage bids and track vacancy revenue",
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              _buildTextField(
                controller: _emailController,
                hint: "Corporate Email Address",
                icon: Icons.business_outlined,
                isEmail: true,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _passwordController,
                hint: "Password",
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isEmail = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: const Color(0xFFD4AF37), size: 20),
        suffixIcon: suffixIcon,
        labelText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: Color(0xFFD4AF37)),
        filled: true,
        fillColor: const Color(0xFF121214),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.03)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.redAccent.withValues(alpha: 0.5),
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return "Required Field";
        if (isEmail && !val.contains("@")) return "Invalid Email";
        return null;
      },
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFD4AF37),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                "CONSOLE SIGN IN",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildSignupLink() {
    return TextButton(
      onPressed: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (c) => const HotelSignupScreen()),
      ),
      child: RichText(
        text: const TextSpan(
          text: "Want to list your property? ",
          style: TextStyle(color: Colors.white, fontSize: 14),
          children: [
            TextSpan(
              text: "Apply Here",
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLuxuryGlow(BoxConstraints constraints) {
    return Positioned(
      bottom: -constraints.maxHeight * 0.2,
      right: -constraints.maxWidth * 0.2,
      child: Container(
        width: constraints.maxWidth * 0.8,
        height: constraints.maxWidth * 0.8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFD4AF37).withValues(alpha: 0.06),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
