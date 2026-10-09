import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/otp.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import 'login.dart';

class HotelSignupScreen extends StatefulWidget {
  const HotelSignupScreen({super.key});

  @override
  State<HotelSignupScreen> createState() => _HotelSignupScreenState();
}

class _HotelSignupScreenState extends State<HotelSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _hotelNameController = TextEditingController();
  final _licenseController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _hotelNameController.dispose();
    _licenseController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;

      // STEP 1: Create user auth credentials cleanly
      final AuthResponse res = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final String? userId = res.user?.id;

      if (userId != null) {
        // STEP 2: Manually insert row into the hotels table matching your schema exactly
        await supabase.from('hotels').insert({
          'id': userId,
          'name': _hotelNameController.text.trim(),
          'hotel_name': _hotelNameController.text.trim(),
          'reg_no': _licenseController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'is_approved': false,
          // Pass a raw WKT Point string instead of an Object Map
          'location':
              'POINT(73.1015 30.6777)', // Format: POINT(longitude latitude)
        });

        if (!mounted) return;

        _showSnackBar("Verification code dispatched!", const Color(0xFFD4AF37));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (c) => HotelOtpScreen(
              userId: userId,
              hotelName: _hotelNameController.text.trim(),
              email: _emailController.text.trim(),
            ),
          ),
        );
      }
    } on AuthException catch (e) {
      _showSnackBar(e.message, Colors.redAccent);
    } on PostgrestException catch (e) {
      // This will catch any specific database column/constraint mismatches directly
      _showSnackBar(
        "Database Configuration error: ${e.message}",
        Colors.redAccent,
      );
      debugPrint("Database Insertion Failure: ${e.details}");
    } catch (e) {
      _showSnackBar("Unexpected configuration error: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 30),
                            _buildGlassCard(),
                            const SizedBox(height: 30),
                            _buildSubmitButton(),
                            const SizedBox(height: 24),
                            _buildLoginLink(),
                          ],
                        ),
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

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(
          Icons.hotel_class_rounded,
          size: 60,
          color: Color(0xFFD4AF37),
        ),
        const SizedBox(height: 16),
        const Text(
          "Negoo Partner",
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "Register your venue to start receiving live bids",
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
          textAlign: TextAlign.center,
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
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              _buildTextField(
                controller: _hotelNameController,
                hint: "Hotel / Property Name",
                icon: Icons.storefront_outlined,
              ),
              const SizedBox(height: 18),
              _buildTextField(
                controller: _licenseController,
                hint: "Business Registration/Reg No",
                icon: Icons.gavel_outlined,
              ),
              const SizedBox(height: 18),
              _buildPhoneField(),
              const SizedBox(height: 18),
              _buildTextField(
                controller: _emailController,
                hint: "Business Email Address",
                icon: Icons.mail_outline,
                isEmail: true,
              ),
              const SizedBox(height: 18),
              _buildTextField(
                controller: _passwordController,
                hint: "Account Password",
                icon: Icons.lock_open_outlined,
                obscure: _obscurePassword,
                isPassword: true,
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
              const SizedBox(height: 18),
              _buildTextField(
                controller: _confirmPasswordController,
                hint: "Confirm Password",
                icon: Icons.lock_outlined,
                obscure: _obscureConfirmPassword,
                isConfirm: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return IntlPhoneField(
      controller: _phoneController,
      dropdownTextStyle: const TextStyle(color: Colors.white),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: const Color(0xFFD4AF37),
      initialCountryCode: 'PK',
      decoration: _inputDecoration(
        "Desk Contact Number",
        Icons.phone_android_outlined,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool isEmail = false,
    bool isPassword = false,
    bool isConfirm = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: _inputDecoration(hint, icon, suffixIcon: suffixIcon),
      validator: (val) {
        if (val == null || val.isEmpty) return "Required field";
        if (isEmail && !val.contains("@")) return "Invalid business email";
        if (isPassword && val.length < 6)
          return "Security requires min 6 chars";
        if (isConfirm && val != _passwordController.text)
          return "Passwords mismatch";
        return null;
      },
    );
  }

  InputDecoration _inputDecoration(
    String hint,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: const Color(0xFFD4AF37), size: 20),
      suffixIcon: suffixIcon,
      labelText: hint,
      labelStyle: const TextStyle(color: Colors.white38, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: Color(0xFFD4AF37)),
      filled: true,
      fillColor: const Color(0xFF121214),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.03)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.15),
            blurRadius: 25,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitRegistration,
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
                "REGISTER VENUE",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return TextButton(
      onPressed: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (c) => const HotelLoginScreen()),
      ),
      child: RichText(
        text: const TextSpan(
          text: "Already managing a property? ",
          style: TextStyle(color: Colors.white, fontSize: 14),
          children: [
            TextSpan(
              text: "Sign In",
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
      top: -constraints.maxHeight * 0.2,
      left: -constraints.maxWidth * 0.2,
      child: Container(
        width: constraints.maxWidth * 0.8,
        height: constraints.maxWidth * 0.8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFFD4AF37).withOpacity(0.08),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
