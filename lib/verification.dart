import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:negoo_hotel_app/pending.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotelVerificationScreen extends StatefulWidget {
  final String userId;
  final String hotelName;

  const HotelVerificationScreen({
    super.key,
    required this.userId,
    required this.hotelName,
  });

  @override
  State<HotelVerificationScreen> createState() =>
      _HotelVerificationScreenState();
}

class _HotelVerificationScreenState extends State<HotelVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _cnicNumberController = TextEditingController();

  int _currentStep = 0;
  bool _isUploading = false;

  File? _logoFile;
  File? _regDocFile;
  File? _cnicFile;
  File? _ownerPhotoFile;

  @override
  void dispose() {
    _cnicNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument(String type) async {
    try {
      final XFile? selected = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (selected == null) return;

      setState(() {
        switch (type) {
          case 'logo':
            _logoFile = File(selected.path);
            break;
          case 'reg':
            _regDocFile = File(selected.path);
            break;
          case 'cnic':
            _cnicFile = File(selected.path);
            break;
          case 'face_recognition': // FIXED: Changed from 'owner' to match 'face_recognition' exactly
            _ownerPhotoFile = File(selected.path);
            break;
        }
      });
    } catch (e) {
      _showSnackBar(
        "Error accessing system gallery storage.",
        Colors.redAccent,
      );
    }
  }

  Future<void> _submitComplianceStack() async {
    if (!_formKey.currentState!.validate()) return;
    if (_logoFile == null ||
        _regDocFile == null ||
        _cnicFile == null ||
        _ownerPhotoFile == null) {
      _showSnackBar(
        "All required verification credentials must be attached.",
        Colors.orangeAccent,
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final supabase = Supabase.instance.client;
      final int timestamp = DateTime.now().millisecondsSinceEpoch;

      Future<String> uploadTask(File file, String destinationBucket) async {
        final String path =
            'verification_vault/${widget.userId}/${destinationBucket}_$timestamp.jpg';
        await supabase.storage.from('verification').upload(path, file);
        return supabase.storage.from('verification').getPublicUrl(path);
      }

      // Concurrently stream all data up cleanly without structural blocks halting
      final List<String> remoteUrls = await Future.wait([
        uploadTask(_logoFile!, 'hotel_logo'),
        uploadTask(_regDocFile!, 'registration_license'),
        uploadTask(_cnicFile!, 'owner_cnic'),
        uploadTask(_ownerPhotoFile!, 'owner_portrait'),
      ]);

      await supabase
          .from('hotels')
          .update({
            'hotel_name': widget.hotelName,
            'name': widget.hotelName,
            'image_url': remoteUrls[0], // Logo
            'document_url': remoteUrls[1], // Registration Document
            'owner_cnic_url': remoteUrls[2], // CNIC Image
            'owner_image_url': remoteUrls[3], // Owner Portrait
            'reg_no': _cnicNumberController.text.trim(),
            'cnic_number': _cnicNumberController.text.trim(),
            'is_approved': false,
          })
          .eq('id', widget.userId);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (c) => HotelPendingScreen(
            userId: widget.userId,
            hotelName: widget.hotelName,
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      _showSnackBar(
        "Compliance payload submission fault: $e",
        Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF121214),
        title: const Text(
          "Compliance Portal",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: _isUploading
          ? _buildLoadingState()
          : Form(key: _formKey, child: _buildStepperWizard()),
    );
  }

  Widget _buildStepperWizard() {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFD4AF37),
          secondary: Color(0xFFD4AF37),
        ),
      ),
      child: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep++);
          } else {
            _submitComplianceStack();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) setState(() => _currentStep--);
        },
        controlsBuilder: (context, details) {
          return Padding(
            padding: const EdgeInsets.only(top: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: details.onStepContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      _currentStep == 2 ? "SUBMIT APPLICATION" : "NEXT STEP",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (_currentStep > 0) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: details.onStepCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("BACK"),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        steps: [
          Step(
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.editing,
            title: const Text(
              "Property Identity Branding",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            content: Column(
              children: [
                _buildUploadContainer(
                  "Hotel Logo / Cover Art",
                  _logoFile,
                  () => _pickDocument('logo'),
                  Icons.storefront_outlined,
                ),
                const SizedBox(height: 16),
                _buildUploadContainer(
                  "Official Registration / Tax Document",
                  _regDocFile,
                  () => _pickDocument('reg'),
                  Icons.gavel_outlined,
                ),
              ],
            ),
          ),
          Step(
            isActive: _currentStep >= 1,
            state: _currentStep > 1
                ? StepState.complete
                : _currentStep == 1
                ? StepState.editing
                : StepState.indexed,
            title: const Text(
              "Managing Partner Protection",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            content: Column(
              children: [
                _buildUploadContainer(
                  "Owner CNIC (Front Card Stack)",
                  _cnicFile,
                  () => _pickDocument('cnic'),
                  Icons.badge_outlined,
                ),
                const SizedBox(height: 16),
                _buildUploadContainer(
                  "Owner Verification Headshot Portrait",
                  _ownerPhotoFile,
                  () => _pickDocument('face_recognition'),
                  Icons.face_outlined,
                ),
              ],
            ),
          ),
          Step(
            isActive: _currentStep >= 2,
            state: _currentStep == 2 ? StepState.editing : StepState.indexed,
            title: const Text(
              "Legal Reference Declaration",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Input the matching identification numbers corresponding with the security files above.",
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _cnicNumberController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: "Owner CNIC / National ID Number",
                    labelStyle: const TextStyle(color: Colors.white38),
                    floatingLabelStyle: const TextStyle(
                      color: Color(0xFFD4AF37),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF121214),
                    prefixIcon: const Icon(
                      Icons.pin_outlined,
                      color: Color(0xFFD4AF37),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                    ),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? "Identification string mapping is critical."
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadContainer(
    String title,
    File? linkedFile,
    VoidCallback action,
    IconData headerIcon,
  ) {
    final bool isReady = linkedFile != null;
    return GestureDetector(
      onTap: action,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isReady ? const Color(0xFF142217) : const Color(0xFF121214),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isReady
                ? Colors.green.withOpacity(0.4)
                : Colors.white.withOpacity(0.04),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isReady ? Icons.check_circle_rounded : headerIcon,
              color: isReady ? Colors.greenAccent : const Color(0xFFD4AF37),
              size: 28,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isReady ? Colors.greenAccent : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isReady
                        ? "Encrypted payload attached"
                        : "Tap to open system storage gallery",
                    style: TextStyle(
                      color: isReady ? Colors.white38 : Colors.white24,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFD4AF37)),
            const SizedBox(height: 24),
            const Text(
              "Securing Documents...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Compressing and uploading credentials safely to our encrypted servers. Please do not close the screen application layout.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
