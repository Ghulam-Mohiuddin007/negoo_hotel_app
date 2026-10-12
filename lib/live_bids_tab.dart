import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:negoo_hotel_app/services/notification_service.dart';
import 'package:negoo_hotel_app/services/redis_cache_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HotelIncomingBidsScreen extends StatefulWidget {
  final String currentHotelId;
  const HotelIncomingBidsScreen({super.key, required this.currentHotelId});

  @override
  State<HotelIncomingBidsScreen> createState() => _HotelIncomingBidsScreenState();
}

class _HotelIncomingBidsScreenState extends State<HotelIncomingBidsScreen> {
  int _lastBidCount = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121214),
        title: const Text(
          "Live Incoming Offers",
          style: TextStyle(
            color: Color(0xFFD4AF37),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('bids')
            .stream(primaryKey: ['id'])
            .eq('hotel_id', widget.currentHotelId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            );
          }

          final allBids = snapshot.data ?? [];
          final liveBidsList = allBids
              .where((bid) => bid['status'] == 'pending')
              .toList();

          // Trigger physical haptic feedback when a new bid is received
          if (liveBidsList.length > _lastBidCount) {
            HapticFeedback.vibrate();
            _lastBidCount = liveBidsList.length;
          } else {
            _lastBidCount = liveBidsList.length;
          }

          if (liveBidsList.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel_rounded, color: Colors.white10, size: 64),
                  SizedBox(height: 16),
                  Text(
                    "Waiting for incoming bid parameters...",
                    style: TextStyle(
                      color: Colors.white24,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: liveBidsList.length,
            itemBuilder: (context, index) {
              return BidTimerCard(bidData: liveBidsList[index]);
            },
          );
        },
      ),
    );
  }
}

class BidTimerCard extends StatefulWidget {
  final Map<String, dynamic> bidData;
  const BidTimerCard({super.key, required this.bidData});

  @override
  State<BidTimerCard> createState() => _BidTimerCardState();
}

class _BidTimerCardState extends State<BidTimerCard> {
  Timer? _countdownTicker;
  int _secondsLeft = 60;
  bool _isProcessingAction = false;

  String _roomType = "Premium Suite";
  double _standardPrice = 0.0;
  String _guestName = "Negoo Traveler";
  bool _isLoadingMetadata = true;

  @override
  void initState() {
    super.initState();
    _calculateClockSyncOffset();
    _startLocalCountdown();
    _fetchMetadata();
  }

  // Fast Redis-cached metadata fetch for room & traveler parameters
  Future<void> _fetchMetadata() async {
    final roomId = widget.bidData['room_id']?.toString() ?? '';
    final userId = widget.bidData['user_id']?.toString() ?? '';
    final redis = RedisCacheService();

    // Check Redis Cache first for 0ms lookup
    final cached = redis.getBidMetadata(roomId, userId);
    if (cached != null) {
      final room = cached['room'] as Map<String, dynamic>?;
      final guest = cached['guest'] as Map<String, dynamic>?;
      if (room != null) {
        _roomType = room['room_type'] ?? "Premium Suite";
        _standardPrice = double.tryParse(room['price'].toString()) ?? 0.0;
      }
      if (guest != null) {
        _guestName = guest['full_name'] ?? "Negoo Traveler";
      }
      _isLoadingMetadata = false;
      if (mounted) setState(() {});
      return;
    }

    try {
      final supabase = Supabase.instance.client;

      Future<Map<String, dynamic>?> roomFuture = Future.value(null);
      if (roomId.isNotEmpty) {
        roomFuture = supabase
            .from('rooms')
            .select('room_type, price')
            .eq('id', roomId)
            .maybeSingle();
      }

      Future<Map<String, dynamic>?> guestFuture = Future.value(null);
      if (userId.isNotEmpty) {
        guestFuture = supabase
            .from('profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
      }

      final results = await Future.wait([roomFuture, guestFuture]);
      final roomData = results[0];
      final guestData = results[1];

      // Save to Redis cache for instant subsequent lookups
      redis.cacheBidMetadata(roomId, userId, {
        'room': roomData,
        'guest': guestData,
      });

      if (mounted) {
        setState(() {
          if (roomData != null) {
            _roomType = roomData['room_type'] ?? "Premium Suite";
            _standardPrice =
                double.tryParse(roomData['price'].toString()) ?? 0.0;
          }
          if (guestData != null) {
            _guestName = guestData['full_name'] ?? "Negoo Traveler";
          }
          _isLoadingMetadata = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading bid metadata: $e");
      if (mounted) {
        setState(() => _isLoadingMetadata = false);
      }
    }
  }

  void _calculateClockSyncOffset() {
    final DateTime targetExpiration = DateTime.parse(
      widget.bidData['expires_at'],
    ).toLocal();
    final DateTime currentSystemTime = DateTime.now();
    final int dynamicDifference =
        targetExpiration.difference(currentSystemTime).inSeconds;

    _secondsLeft = dynamicDifference > 0 ? dynamicDifference : 0;
  }

  void _startLocalCountdown() {
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        _countdownTicker?.cancel();
        _executeAutomaticTimeoutTermination();
      }
    });
  }

  Future<void> _executeAutomaticTimeoutTermination() async {
    if (_isProcessingAction) return;
    _isProcessingAction = true;
    try {
      await Supabase.instance.client
          .from('bids')
          .update({'status': 'expired'})
          .eq('id', widget.bidData['id']);
    } catch (e) {
      debugPrint("Timeout execution failure update: $e");
    }
  }

  Future<void> _updateBidStatus(bool approveAllocation) async {
    setState(() => _isProcessingAction = true);
    try {
      _countdownTicker?.cancel();
      await Supabase.instance.client
          .from('bids')
          .update({'status': approveAllocation ? 'accepted' : 'declined'})
          .eq('id', widget.bidData['id']);

      // Instant Realtime Notification to Guest
      if (widget.bidData['user_id'] != null) {
        NotificationService().sendNotificationToUser(
          userId: widget.bidData['user_id'].toString(),
          title: approveAllocation ? "Deal Secured! 🎉" : "Offer Declined ❌",
          body: approveAllocation
              ? "The hotel accepted your rate match proposal (PKR ${widget.bidData['bid_amount']})!"
              : "The hotel passed on your proposed rate of PKR ${widget.bidData['bid_amount']}.",
          data: {
            'bid_id': widget.bidData['id'],
            'status': approveAllocation ? 'accepted' : 'declined',
          },
        );
      }

      if (approveAllocation) {
        ToastService.success("Bid accepted!");
      } else {
        ToastService.info("Bid declined.");
      }
    } catch (e) {
      debugPrint("Status transmission failed: $e");
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0) return const SizedBox.shrink();

    final progress = _secondsLeft / 60.0;
    final progressColor =
        _secondsLeft <= 15 ? Colors.redAccent : const Color(0xFFD4AF37);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _secondsLeft <= 15
              ? Colors.redAccent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.03),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info: Guest & Room type
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _guestName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _roomType,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _secondsLeft <= 15
                      ? Colors.red.withValues(alpha: 0.1)
                      : const Color(0xFFD4AF37).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: _secondsLeft <= 15
                        ? Colors.redAccent.withValues(alpha: 0.3)
                        : const Color(0xFFD4AF37).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  "${_secondsLeft}s left",
                  style: TextStyle(
                    color: _secondsLeft <= 15
                        ? Colors.redAccent
                        : const Color(0xFFD4AF37),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Price comparison details
          if (!_isLoadingMetadata) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Standard Price",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "PKR ${_standardPrice.toStringAsFixed(0)}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white24,
                  size: 16,
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      "Proposed Offer",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "PKR ${widget.bidData['bid_amount']}",
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // Shrinking time indicator line
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 20),
          // Actions: Decline or Accept
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isProcessingAction
                      ? null
                      : () => _updateBidStatus(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "DECLINE",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isProcessingAction
                      ? null
                      : () => _updateBidStatus(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isProcessingAction
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "ACCEPT DEAL",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
