import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/otp.dart';
import 'package:negoo_hotel_app/services/location_service.dart';
import 'package:negoo_hotel_app/widgets/location_picker_sheet.dart';
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
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();

  HotelLocationData? _selectedLocation;
  bool _isLoading = false;
  bool _isAutoFetchingLocation = false;
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
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _openLocationPicker() async {
    final loc = await LocationPickerSheet.show(
      context,
      initialLocation: _selectedLocation,
    );
    if (loc != null && mounted) {
      setState(() {
        _selectedLocation = loc;
        _addressController.text = loc.address;
        _cityController.text = loc.city;
      });
    }
  }

  Future<void> _quickAutoFetchGps() async {
    setState(() => _isAutoFetchingLocation = true);
    try {
      final loc = await LocationService().getCurrentLocationWithAddress();
      if (loc != null && mounted) {
        setState(() {
          _selectedLocation = loc;
          _addressController.text = loc.address;
          _cityController.text = loc.city;
        });
        _showSnackBar(
          "Auto-fetched hotel GPS coordinates & address! 📍",
          const Color(0xFFD4AF37),
        );
      } else if (mounted) {
        _showSnackBar(
          "Could not auto-fetch GPS. Opening Maps search...",
          Colors.orangeAccent,
        );
        _openLocationPicker();
      }
    } finally {
      if (mounted) setState(() => _isAutoFetchingLocation = false);
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedLocation == null && _addressController.text.trim().isEmpty) {
      _showSnackBar(
        "Please specify your hotel location using Maps or auto-fetch.",
        Colors.orangeAccent,
      );
      return;
    }

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
        final locationData = _selectedLocation ??
            HotelLocationData(
              address: _addressController.text.trim(),
              city: _cityController.text.trim().isNotEmpty
                  ? _cityController.text.trim()
                  : "Lahore",
              latitude: 31.5204,
              longitude: 74.3587,
            );

        // STEP 2: Insert row into the hotels table matching PostGIS schema
        await supabase.from('hotels').insert({
          'id': userId,
          'name': _hotelNameController.text.trim(),
          'hotel_name': _hotelNameController.text.trim(),
          'reg_no': _licenseController.text.trim(),
          'phone_number': _phoneController.text.trim(),
          'address': locationData.address,
          'city': locationData.city,
          'is_approved': false,
          // PostGIS POINT(longitude latitude) format
          'location': locationData.toWktPoint(),
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
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 28),
                            _buildGlassCard(),
                            const SizedBox(height: 28),
                            _buildSubmitButton(),
                            const SizedBox(height: 20),
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
          "Register your venue with live Google Maps geotagging",
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
            crossAxisAlignment: CrossAxisAlignment.start,
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

              const SizedBox(height: 20),
              // Hotel Location Section
              _buildLocationSection(),

              const SizedBox(height: 20),
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

  /// Hotel Location & Google Maps Auto-fetch selector component
  Widget _buildLocationSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _selectedLocation != null
              ? const Color(0xFFD4AF37).withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on, color: Color(0xFFD4AF37), size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Hotel Venue Location",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (_selectedLocation != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "GEO-TAGGED",
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Auto-fetch coordinates using Google Maps or GPS satellite lock",
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
          ),
          const SizedBox(height: 14),

          // Action buttons: Search on Maps vs Quick GPS
          Row(
            children: [
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: _openLocationPicker,
                  icon: const Icon(Icons.map_outlined, size: 16, color: Color(0xFFD4AF37)),
                  label: Text(
                    _selectedLocation != null ? "Change Pin" : "Search on Maps",
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: const Color(0xFFD4AF37).withOpacity(0.4)),
                    backgroundColor: const Color(0xFFD4AF37).withOpacity(0.04),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: ElevatedButton.icon(
                  onPressed: _isAutoFetchingLocation ? null : _quickAutoFetchGps,
                  icon: _isAutoFetchingLocation
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.my_location, size: 16, color: Colors.black),
                  label: Text(
                    _isAutoFetchingLocation ? "Locating..." : "Auto-Fetch GPS",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),

          // Display selected address and coordinates
          if (_selectedLocation != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.04)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 14, color: Colors.white54),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _selectedLocation!.address,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _selectedLocation!.city,
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${_selectedLocation!.latitude.toStringAsFixed(4)}°, ${_selectedLocation!.longitude.toStringAsFixed(4)}°",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            _buildTextField(
              controller: _addressController,
              hint: "Street Address or Commercial Landmark",
              icon: Icons.edit_location_alt_outlined,
            ),
            const SizedBox(height: 10),
            _buildTextField(
              controller: _cityController,
              hint: "City (e.g. Lahore, Islamabad)",
              icon: Icons.location_city_outlined,
            ),
          ],
        ],
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
        if (isPassword && val.length < 6) return "Security requires min 6 chars";
        if (isConfirm && val != _passwordController.text) return "Passwords mismatch";
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
