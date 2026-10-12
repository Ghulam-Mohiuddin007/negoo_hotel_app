import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoomsTabScreen extends StatefulWidget {
  final String userId;
  const RoomsTabScreen({super.key, required this.userId});

  @override
  State<RoomsTabScreen> createState() => _RoomsTabScreenState();
}

class _RoomsTabScreenState extends State<RoomsTabScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _supabase = Supabase.instance.client;

  // Form Controllers
  final _roomTypeController = TextEditingController();
  final _roomPriceController = TextEditingController();
  final _roomDescController = TextEditingController();
  final _bedTypeController = TextEditingController(text: "King Size");
  final _guestsController = TextEditingController(text: "2");
  final _amenitiesController = TextEditingController(
    text: "Free Wi-Fi, AC, Smart TV",
  );

  List<File> _selectedImages = [];
  bool _isActionLoading = false;
  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    // 1. Read from Redis Cache immediately for 0ms render
    final cached = RedisCacheService().getCachedRooms(widget.userId);
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _rooms = cached;
        _isLoading = false;
      });
    }

    try {
      final List<dynamic> data = await _supabase
          .from('rooms')
          .select()
          .eq('hotel_id', widget.userId);
      final freshRooms = List<Map<String, dynamic>>.from(data);
      await RedisCacheService().cacheRooms(widget.userId, freshRooms);
      if (mounted) {
        setState(() {
          _rooms = freshRooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching rooms: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _roomTypeController.dispose();
    _roomPriceController.dispose();
    _roomDescController.dispose();
    _bedTypeController.dispose();
    _guestsController.dispose();
    _amenitiesController.dispose();
    super.dispose();
  }

  // Multi-Image Gallery Picker Sequence Loop
  Future<void> _pickRoomImages() async {
    if (_selectedImages.length >= 5) {
      _showSnackBar("Maximum limit of 5 images reached.", Colors.orangeAccent);
      return;
    }
    try {
      final List<XFile> images = await _picker.pickMultiImage(imageQuality: 60);
      if (images.isEmpty) return;

      setState(() {
        _selectedImages.addAll(images.map((img) => File(img.path)));
        if (_selectedImages.length > 5) {
          _selectedImages = _selectedImages.sublist(0, 5);
          _showSnackBar(
            "Trimmed asset stack to top 5 selected items.",
            const Color(0xFFD4AF37),
          );
        }
      });
    } catch (e) {
      _showSnackBar(
        "Error reading external local storage assets.",
        Colors.redAccent,
      );
    }
  }

  // Helper pipeline to stream local assets into storage bucket repositories
  Future<List<String>> _uploadImageStack(
    List<File> files,
    String roomId,
  ) async {
    List<String> deployedUrls = [];
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < files.length; i++) {
      final String path =
          'room_vault/${widget.userId}/room_$roomId/img_${i}_$timestamp.jpg';
      await _supabase.storage.from('verification').upload(path, files[i]);
      final String publicUrl = _supabase.storage
          .from('verification')
          .getPublicUrl(path);
      deployedUrls.add(publicUrl);
    }
    return deployedUrls;
  }

  Future<void> _publishNewInventory() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isActionLoading = true);

    try {
      final double cleanPrice = double.parse(_roomPriceController.text.trim());
      final int maxGuests = int.tryParse(_guestsController.text.trim()) ?? 2;
      final List<String> amenitiesList = _amenitiesController.text
          .split(',')
          .map((e) => e.trim())
          .toList();

      // 1. Generate local target index reference row
      final targetRoomRow = await _supabase
          .from('rooms')
          .insert({
            'hotel_id': widget.userId,
            'room_type': _roomTypeController.text.trim(),
            'price': cleanPrice,
            'description': _roomDescController.text.trim().isEmpty
                ? null
                : _roomDescController.text.trim(),
            'bed_type': _bedTypeController.text.trim(),
            'max_guests': maxGuests,
            'amenities': amenitiesList,
          })
          .select()
          .single();

      final String newlyCreatedRoomId = targetRoomRow['id'].toString();

      // 2. Process imagery if attached to stack
      List<String> remoteUrls = [];
      if (_selectedImages.isNotEmpty) {
        remoteUrls = await _uploadImageStack(
          _selectedImages,
          newlyCreatedRoomId,
        );

        // Push remote url array directly into targeted column placeholder fields
        await _supabase
            .from('rooms')
            .update({
              'room_images': remoteUrls,
              'image_url': remoteUrls
                  .first, // Primary thumbnail mapping fallback pointer
            })
            .eq('id', newlyCreatedRoomId);
      }

      if (!mounted) return;
      Navigator.pop(context);
      _clearFormFields();
      _showSnackBar(
        "Suite variant registered and published live.",
        Colors.green.shade800,
      );
      _fetchRooms();
    } catch (e) {
      _showSnackBar("Publish error: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _clearFormFields() {
    _roomTypeController.clear();
    _roomPriceController.clear();
    _roomDescController.clear();
    _selectedImages.clear();
    _bedTypeController.text = "King Size";
    _guestsController.text = "2";
    _amenitiesController.text = "Free Wi-Fi, AC, Smart TV";
  }

  void _showSnackBar(String msg, Color color) {
    if (color == Colors.redAccent || color == Colors.red) {
      ToastService.error(msg);
    } else if (color == Colors.orangeAccent || color == Colors.amber) {
      ToastService.warning(msg);
    } else if (color == Colors.green) {
      ToastService.success(msg);
    } else {
      ToastService.info(msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _displayAddRoomSheet(context),
        backgroundColor: const Color(0xFFD4AF37),
        foregroundColor: Colors.black,
        elevation: 4,
        icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
        label: const Text(
          "NEW SUITE VARIANT",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            )
          : _rooms.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: _rooms.length,
                  itemBuilder: (context, index) {
                    final roomItem = _rooms[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _openRoomInspectionHub(
                        roomItem,
                      ), // Makes each room clickable!
                      child: _buildPremiumRoomCard(roomItem),
                    );
                  },
                ),
    );
  }

  Widget _buildPremiumRoomCard(Map<String, dynamic> roomItem) {
    final List<dynamic> images = roomItem['room_images'] ?? [];
    final String? primaryThumb = images.isNotEmpty ? images.first : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Dynamic Network Image/Asset Shell box frame
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.01),
                  borderRadius: BorderRadius.circular(14),
                  image: primaryThumb != null
                      ? DecorationImage(
                          image: NetworkImage(primaryThumb),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: primaryThumb == null
                    ? const Icon(
                        Icons.king_bed_outlined,
                        color: Color(0xFFD4AF37),
                        size: 24,
                      )
                    : null,
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomItem['room_type'] ?? 'Standard Suite',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${roomItem['bed_type']} • Max Guests: ${roomItem['max_guests']}",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    "RATE",
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "PKR \\${roomItem['price']}",
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // SCREEN MODAL SHEET 1: Add New Room Onboarding Script Workflow
  void _displayAddRoomSheet(BuildContext context) {
    _clearFormFields();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121214),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Configure Suite Profile",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Image Strip picker block
                  const Text(
                    "ROOM IMAGES (UP TO 5)",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildImageSelectionBar(() async {
                    await _pickRoomImages();
                    setModalState(() {});
                  }),
                  const SizedBox(height: 20),

                  _buildPremiumField(
                    controller: _roomTypeController,
                    label: "Room Designation Name",
                    hint: "e.g., Luxury Executive Suite",
                    icon: Icons.king_bed_outlined,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _buildPremiumField(
                          controller: _roomPriceController,
                          label: "Price per Night (PKR)",
                          hint: "8500",
                          icon: Icons.payments_outlined,
                          inputType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPremiumField(
                          controller: _guestsController,
                          label: "Max Guests",
                          hint: "2",
                          icon: Icons.people_outline,
                          inputType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPremiumField(
                          controller: _bedTypeController,
                          label: "Bed Setup Type",
                          hint: "King Size / Twin",
                          icon: Icons.bed_outlined,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPremiumField(
                          controller: _amenitiesController,
                          label: "Amenities (Comma Split)",
                          hint: "AC, WiFi, Pool",
                          icon: Icons.star_border,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildPremiumField(
                    controller: _roomDescController,
                    label: "Suite Overview Description",
                    hint: "Provide details about the stay...",
                    icon: Icons.notes_rounded,
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isActionLoading
                          ? null
                          : () async {
                              setModalState(() => _isActionLoading = true);
                              await _publishNewInventory();
                              setModalState(() => _isActionLoading = false);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isActionLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : const Text(
                              "PUBLISH INVENTORY PORTAL",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // SCREEN MODAL SHEET 2: Room Interactive Detail Modification Hub
  void _openRoomInspectionHub(Map<String, dynamic> initialData) {
    final editPriceController = TextEditingController(
      text: initialData['price'].toString(),
    );
    final editDescController = TextEditingController(
      text: initialData['description'] ?? '',
    );
    final List<dynamic> currentUploadedUrls = initialData['room_images'] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F11),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setEditState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top header controls row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      initialData['room_type'] ?? 'Edit Room Suite',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_sweep_outlined,
                        color: Colors.redAccent,
                      ),
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        await _supabase
                            .from('rooms')
                            .delete()
                            .eq('id', initialData['id']);
                        if (!mounted) return;
                        nav.pop();
                        _showSnackBar(
                          "Suite parameters permanently purged.",
                          Colors.orange,
                        );
                        _fetchRooms();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Absolute network imagery loop display slider
                if (currentUploadedUrls.isNotEmpty) ...[
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: currentUploadedUrls.length,
                      itemBuilder: (context, i) => Container(
                        width: 140,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          image: DecorationImage(
                            image: NetworkImage(currentUploadedUrls[i]),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                _buildPremiumField(
                  controller: editPriceController,
                  label: "Modify Pricing Rate (PKR)",
                  hint: "Price",
                  icon: Icons.money,
                  inputType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _buildPremiumField(
                  controller: editDescController,
                  label: "Modify Overview Text",
                  hint: "Description",
                  icon: Icons.edit_note_outlined,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      await _supabase
                          .from('rooms')
                          .update({
                            'price': double.parse(
                              editPriceController.text.trim(),
                            ),
                            'description': editDescController.text.trim(),
                          })
                          .eq('id', initialData['id']);
                      if (!mounted) return;
                      nav.pop();
                      _showSnackBar(
                        "Suite registers modified successfully.",
                        Colors.green,
                      );
                      _fetchRooms();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD4AF37),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "SAVE ALTERATION LOGS",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Structural sub-render atomic view builders
  Widget _buildImageSelectionBar(VoidCallback onAddTap) {
    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length + 1,
        itemBuilder: (context, idx) {
          if (idx == _selectedImages.length) {
            return GestureDetector(
              onTap: onAddTap,
              child: Container(
                width: 70,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: Color(0xFFD4AF37),
                  size: 20,
                ),
              ),
            );
          }
          return Container(
            width: 70,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              image: DecorationImage(
                image: FileImage(_selectedImages[idx]),
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPremiumField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      validator: validator,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Color(0xFFD4AF37)),
        filled: true,
        fillColor: const Color(0xFF09090B),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
          size: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.02)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.2),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bed_outlined,
            size: 54,
            color: Colors.white.withValues(alpha: 0.05),
          ),
          const SizedBox(height: 16),
          const Text(
            "No Suites Discovered",
            style: TextStyle(
              color: Colors.white38,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
