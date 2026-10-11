import 'package:flutter/material.dart';
import 'package:negoo_hotel_app/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FinancialsTabScreen extends StatefulWidget {
  final String userId;
  const FinancialsTabScreen({super.key, required this.userId});

  @override
  State<FinancialsTabScreen> createState() => _FinancialsTabScreenState();
}

class _FinancialsTabScreenState extends State<FinancialsTabScreen> {
  late final SupabaseClient _supabase;
  bool _isActionLoading = false;
  String _hotelName = "Hotel Partner";
  String _activeFilter = 'all'; // 'all', 'pending', 'confirmed', 'unpaid_commission'

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    _fetchHotelName();
  }

  Future<void> _fetchHotelName() async {
    try {
      final data = await _supabase
          .from('hotels')
          .select('hotel_name, name')
          .eq('id', widget.userId)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _hotelName = data['hotel_name'] ?? data['name'] ?? "Hotel Partner";
        });
      }
    } catch (_) {}
  }

  /// Updates booking status and immediately notifies the customer in real-time
  Future<void> _updateBookingStatus(
    Map<String, dynamic> booking,
    String targetStatus, {
    bool closeDetailSheet = false,
  }) async {
    final String bookingId = booking['id'].toString();
    final String? customerUserId = booking['user_id']?.toString();
    final roomData = booking['rooms'] as Map<String, dynamic>?;
    final String roomDesignation = roomData?['room_type'] ?? 'Standard Suite';
    final String guestName = booking['full_name'] ?? 'Guest';

    setState(() => _isActionLoading = true);

    try {
      // 1. Update booking status in PostgreSQL database
      await _supabase
          .from('bookings')
          .update({
            'status': targetStatus,
            'confirmed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', bookingId);

      // 2. If confirmed, notify the customer immediately via Supabase Realtime broadcast & notifications table
      if (targetStatus == 'confirmed' && customerUserId != null && customerUserId.isNotEmpty) {
        // Send Realtime Broadcast directly to customer's personal channel
        await NotificationService().sendNotificationToUser(
          userId: customerUserId,
          title: "Booking Confirmed! 🎉",
          body: "Dear $guestName, your reservation at $_hotelName ($roomDesignation) is confirmed! Get ready for your stay.",
          data: {
            'booking_id': bookingId,
            'status': 'confirmed',
            'hotel_id': widget.userId,
            'hotel_name': _hotelName,
            'room_type': roomDesignation,
            'guest_name': guestName,
            'total_price': booking['total_price'],
          },
        );

        // Persist notification in database for guest's notifications inbox
        try {
          await _supabase.from('notifications').insert({
            'user_id': customerUserId,
            'hotel_id': widget.userId,
            'title': "Booking Confirmed! 🎉",
            'body': "Your reservation at $_hotelName ($roomDesignation) has been confirmed by the hotel.",
            'type': 'booking_confirmed',
            'data': {
              'booking_id': bookingId,
              'status': 'confirmed',
              'hotel_id': widget.userId,
              'hotel_name': _hotelName,
              'room_type': roomDesignation,
            },
            'is_read': false,
          });
        } catch (e) {
          debugPrint("Non-critical notification insert warning: $e");
        }
      }

      if (!mounted) return;
      if (closeDetailSheet) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      _showSnackBar(
        targetStatus == 'confirmed'
            ? "Booking confirmed! Customer has been notified in real time. 🎉"
            : "Booking declined and reservation slot released.",
        targetStatus == 'confirmed' ? const Color(0xFF2E7D32) : Colors.orange.shade800,
      );

      setState(() {});
    } catch (e) {
      _showSnackBar("Execution failure: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  /// Mark Negoo commission as settled for a specific booking
  Future<void> _toggleCommissionSettled(Map<String, dynamic> booking) async {
    final String bookingId = booking['id'].toString();
    final bool currentSettled = booking['commission_paid'] == true ||
        booking['commission_status'] == 'paid';
    final bool newSettled = !currentSettled;

    setState(() => _isActionLoading = true);
    try {
      await _supabase
          .from('bookings')
          .update({
            'commission_paid': newSettled,
            'commission_status': newSettled ? 'paid' : 'unpaid',
            'commission_settled_at': newSettled ? DateTime.now().toIso8601String() : null,
          })
          .eq('id', bookingId);

      if (!mounted) return;
      _showSnackBar(
        newSettled
            ? "Negoo commission marked as Settled/Paid for this booking."
            : "Negoo commission marked as Unpaid.",
        newSettled ? Colors.green.shade800 : const Color(0xFFD4AF37),
      );
      setState(() {});
    } catch (e) {
      _showSnackBar("Settlement update error: $e", Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PostgrestList>(
      future: _supabase
          .from('bookings')
          .select('*, rooms!fk_room(room_type, hotel_id)')
          .eq('rooms.hotel_id', widget.userId)
          .order('created_at', ascending: false),
      builder: (context, futureSnapshot) {
        if (futureSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
          );
        }

        final historicalRecords = (futureSnapshot.data ?? []).where((booking) {
          final roomData = booking['rooms'] as Map<String, dynamic>?;
          return roomData != null && roomData['hotel_id'] == widget.userId;
        }).toList();

        // 1. Calculate Financial Statements
        double totalEarningsGross = 0.0;
        double confirmedCommissionTotal = 0.0;
        double paidCommissionToNegoo = 0.0;
        double unpaidAmountToNegoo = 0.0;

        int pendingCount = 0;
        int confirmedCount = 0;
        int unpaidCommissionBookingsCount = 0;

        for (var tx in historicalRecords) {
          final status = tx['status']?.toString().toLowerCase();
          final price = double.tryParse(tx['total_price'].toString()) ?? 0.0;

          if (status == 'pending') {
            pendingCount++;
          } else if (status == 'confirmed') {
            confirmedCount++;
            totalEarningsGross += price;
            final commission = price * 0.10; // Negoo 10% commission
            confirmedCommissionTotal += commission;

            final bool isPaid = tx['commission_paid'] == true ||
                tx['commission_status'] == 'paid';
            if (isPaid) {
              paidCommissionToNegoo += commission;
            } else {
              unpaidAmountToNegoo += commission;
              unpaidCommissionBookingsCount++;
            }
          }
        }

        final double netRetainedBalance = totalEarningsGross - confirmedCommissionTotal;

        // 2. Filter historical records according to active tab
        List<Map<String, dynamic>> filteredRecords = historicalRecords;
        if (_activeFilter == 'pending') {
          filteredRecords = historicalRecords.where((b) => b['status'] == 'pending').toList();
        } else if (_activeFilter == 'confirmed') {
          filteredRecords = historicalRecords.where((b) => b['status'] == 'confirmed').toList();
        } else if (_activeFilter == 'unpaid_commission') {
          filteredRecords = historicalRecords.where((b) {
            final isConfirmed = b['status'] == 'confirmed';
            final isPaid = b['commission_paid'] == true || b['commission_status'] == 'paid';
            return isConfirmed && !isPaid;
          }).toList();
        }

        return RefreshIndicator(
          color: const Color(0xFFD4AF37),
          backgroundColor: const Color(0xFF121214),
          onRefresh: () async => setState(() {}),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Financial Matrix",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          "Total Earnings • Negoo Commission • Unpaid Dues",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      tooltip: "Refresh Ledger",
                      icon: const Icon(Icons.refresh, color: Color(0xFFD4AF37)),
                      onPressed: () => setState(() {}),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Premium Financial Breakdown & Unpaid Negoo Commission Card
                _buildComprehensiveFinancialsCard(
                  gross: totalEarningsGross,
                  commission: confirmedCommissionTotal,
                  unpaidToNegoo: unpaidAmountToNegoo,
                  paidCommission: paidCommissionToNegoo,
                  netBalance: netRetainedBalance,
                ),

                const SizedBox(height: 16),

                // Settle Dues / Negoo Commission Info Banner
                _buildNegooCommissionBanner(unpaidAmountToNegoo, unpaidCommissionBookingsCount),

                const SizedBox(height: 30),

                // Reservation Queue Title & Filter Chips
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Reservation Queue",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      "${filteredRecords.length} records",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Filters
                _buildFilterChips(
                  allCount: historicalRecords.length,
                  pendingCount: pendingCount,
                  confirmedCount: confirmedCount,
                  unpaidCount: unpaidCommissionBookingsCount,
                ),

                const SizedBox(height: 16),

                // Booking List
                if (filteredRecords.isEmpty)
                  _buildEmptyState()
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredRecords.length,
                    itemBuilder: (context, index) {
                      final booking = filteredRecords[index];
                      return _buildBookingItemRow(booking);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Main Financials Card displaying Total Earnings, Negoo Commission, Unpaid Amount, and Net Balance
  Widget _buildComprehensiveFinancialsCard({
    required double gross,
    required double commission,
    required double unpaidToNegoo,
    required double paidCommission,
    required double netBalance,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                // 1. Total Earning
                _buildLedgerRow(
                  "Total Gross Earning",
                  "PKR ${gross.toStringAsFixed(0)}",
                  Colors.white,
                  isPrimary: true,
                  icon: Icons.account_balance_wallet_outlined,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10, height: 1),
                ),

                // 2. Negoo Marketplace Commission (10%)
                _buildLedgerRow(
                  "Negoo Commission (10%)",
                  "- PKR ${commission.toStringAsFixed(0)}",
                  Colors.redAccent.shade100,
                  icon: Icons.pie_chart_outline_rounded,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10, height: 1),
                ),

                // 3. Unpaid Amount to Negoo (Highlighted Alert Metric)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: unpaidToNegoo > 0
                        ? Colors.amber.withOpacity(0.08)
                        : Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: unpaidToNegoo > 0
                          ? Colors.amber.withOpacity(0.3)
                          : Colors.green.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            unpaidToNegoo > 0
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            size: 18,
                            color: unpaidToNegoo > 0 ? Colors.amber : Colors.greenAccent,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Unpaid Amount to Negoo",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                unpaidToNegoo > 0 ? "Pending remittance to Negoo" : "All commissions settled",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(
                        "PKR ${unpaidToNegoo.toStringAsFixed(0)}",
                        style: TextStyle(
                          color: unpaidToNegoo > 0 ? Colors.amberAccent : Colors.greenAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Net Disbursable Balance footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Net Hotel Retained Earning",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      "Gross minus 10% platform fee",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                Text(
                  "PKR ${netBalance.toStringAsFixed(0)}",
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Banner explaining Negoo Commission and offering Settlement Actions
  Widget _buildNegooCommissionBanner(double unpaidAmount, int unpaidCount) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFFD4AF37),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Negoo Marketplace Fee Settlement",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unpaidAmount > 0
                      ? "$unpaidCount bookings pending commission payment of PKR ${unpaidAmount.toStringAsFixed(0)}"
                      : "Zero outstanding dues. All bookings settled cleanly.",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _displaySettlementDetailsSheet(unpaidAmount),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text(
              "Dues Details",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Filter chips for quick switching between booking states
  Widget _buildFilterChips({
    required int allCount,
    required int pendingCount,
    required int confirmedCount,
    required int unpaidCount,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildChip('all', "All ($allCount)"),
          const SizedBox(width: 8),
          _buildChip('pending', "Pending ($pendingCount)", badgeColor: Colors.amberAccent),
          const SizedBox(width: 8),
          _buildChip('confirmed', "Confirmed ($confirmedCount)", badgeColor: Colors.greenAccent),
          const SizedBox(width: 8),
          _buildChip('unpaid_commission', "Unpaid Dues ($unpaidCount)", badgeColor: Colors.orangeAccent),
        ],
      ),
    );
  }

  Widget _buildChip(String filterKey, String label, {Color? badgeColor}) {
    final bool isSelected = _activeFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filterKey),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4AF37)
                : (badgeColor?.withOpacity(0.3) ?? Colors.white.withOpacity(0.06)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : (badgeColor ?? Colors.white70),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  /// Booking row with Quick Confirm and Decline actions
  Widget _buildBookingItemRow(Map<String, dynamic> booking) {
    final roomData = booking['rooms'] as Map<String, dynamic>?;
    final String roomDesignation = roomData?['room_type'] ?? 'Standard Suite';
    final String status = booking['status'] ?? 'pending';
    final double price = double.tryParse(booking['total_price'].toString()) ?? 0.0;
    final double negooCut = price * 0.10;
    final bool isCommissionSettled =
        booking['commission_paid'] == true || booking['commission_status'] == 'paid';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status == 'pending'
              ? const Color(0xFFD4AF37).withOpacity(0.3)
              : Colors.white.withOpacity(0.03),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _displayBookingDetailsSheet(booking, roomDesignation),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.02),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      status == 'confirmed'
                          ? Icons.check_circle_outline_rounded
                          : status == 'rejected'
                              ? Icons.remove_circle_outline_rounded
                              : Icons.pending_actions_rounded,
                      color: status == 'confirmed'
                          ? Colors.greenAccent
                          : status == 'rejected'
                              ? Colors.redAccent
                              : const Color(0xFFD4AF37),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking['full_name'] ?? 'Guest Traveler',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          roomDesignation,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 13,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Commission badge for confirmed bookings
                        if (status == 'confirmed')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isCommissionSettled
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCommissionSettled
                                  ? "Negoo Fee (PKR ${negooCut.toStringAsFixed(0)}): Settled"
                                  : "Negoo Fee (PKR ${negooCut.toStringAsFixed(0)}): Unpaid",
                              style: TextStyle(
                                color: isCommissionSettled ? Colors.greenAccent : Colors.orangeAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "PKR ${booking['total_price']}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(status),
                    ],
                  ),
                ],
              ),

              // Quick Action Buttons if pending
              if (status == 'pending') ...[
                const SizedBox(height: 14),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isActionLoading
                            ? null
                            : () => _updateBookingStatus(booking, 'rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Decline", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _isActionLoading
                            ? null
                            : () => _updateBookingStatus(booking, 'confirmed'),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text(
                          "CONFIRM BOOKING",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Full Booking Details Sheet with Confirm action and customer notification
  void _displayBookingDetailsSheet(
    Map<String, dynamic> booking,
    String roomType,
  ) {
    final String currentStatus = booking['status'] ?? 'pending';
    final double price = double.tryParse(booking['total_price'].toString()) ?? 0.0;
    final double negooFee = price * 0.10;
    final double hotelNet = price - negooFee;
    final bool isCommissionSettled =
        booking['commission_paid'] == true || booking['commission_status'] == 'paid';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121214),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Reservation Sheet",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _buildStatusBadge(currentStatus),
                ],
              ),
              const SizedBox(height: 20),

              _buildDetailInvoiceRow(
                Icons.person_outline_rounded,
                "Lead Guest",
                booking['full_name'] ?? 'N/A',
              ),
              _buildDetailInvoiceRow(
                Icons.phone_enabled_outlined,
                "Contact Number",
                booking['phone'] ?? 'N/A',
              ),
              _buildDetailInvoiceRow(
                Icons.badge_outlined,
                "National CNIC",
                booking['cnic'] ?? 'N/A',
              ),
              _buildDetailInvoiceRow(
                Icons.meeting_room_outlined,
                "Suite Type",
                roomType,
              ),
              _buildDetailInvoiceRow(
                Icons.people_outline_rounded,
                "Guests Count",
                "${booking['guest_count'] ?? 1} Persons",
              ),
              _buildDetailInvoiceRow(
                Icons.date_range_outlined,
                "Stay Duration",
                "${booking['stay_from']} to ${booking['stay_to']}",
              ),
              _buildDetailInvoiceRow(
                Icons.payment_rounded,
                "Payment Method",
                (booking['payment_method'] ?? 'cash at hotel').toString().toUpperCase(),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Colors.white10),
              ),

              // Financial breakdown for this booking
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.04)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Gross Booking Price", style: TextStyle(color: Colors.white70, fontSize: 13)),
                        Text("PKR ${price.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Negoo Marketplace Fee (10%)", style: TextStyle(color: Colors.white54, fontSize: 13)),
                        Text("- PKR ${negooFee.toStringAsFixed(0)}", style: TextStyle(color: Colors.redAccent.shade100, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Hotel Net Retained", style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("PKR ${hotelNet.toStringAsFixed(0)}", style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                  ],
                ),
              ),

              // Commission settlement toggle if confirmed
              if (currentStatus == 'confirmed') ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isCommissionSettled
                          ? "Negoo Fee Status: Settled"
                          : "Negoo Fee Status: Unpaid",
                      style: TextStyle(
                        color: isCommissionSettled ? Colors.greenAccent : Colors.orangeAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleCommissionSettled(booking);
                      },
                      icon: Icon(
                        isCommissionSettled ? Icons.undo : Icons.check_circle_outline,
                        size: 16,
                        color: const Color(0xFFD4AF37),
                      ),
                      label: Text(
                        isCommissionSettled ? "Mark as Unpaid" : "Mark Commission Paid",
                        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              if (currentStatus == 'pending')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isActionLoading
                            ? null
                            : () => _updateBookingStatus(
                                  booking,
                                  'rejected',
                                  closeDetailSheet: true,
                                ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text("DECLINE OFFER", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isActionLoading
                            ? null
                            : () => _updateBookingStatus(
                                  booking,
                                  'confirmed',
                                  closeDetailSheet: true,
                                ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _isActionLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : const Text("CONFIRM BOOKING", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back, size: 16, color: Colors.white54),
                    label: const Text("CLOSE LEDGER", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  /// Negoo Commission Settlement Details Modal
  void _displaySettlementDetailsSheet(double unpaidDues) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121214),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Negoo Dues Settlement",
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: unpaidDues > 0 ? Colors.amber.withOpacity(0.15) : Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unpaidDues > 0 ? "PKR ${unpaidDues.toStringAsFixed(0)} DUE" : "SETTLED",
                    style: TextStyle(
                      color: unpaidDues > 0 ? Colors.amberAccent : Colors.greenAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Negoo platform fee is 10% on confirmed bookings collected from direct guest payments.",
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
            ),
            const SizedBox(height: 20),

            // Remittance Accounts Box
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF16161A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Official Negoo Remittance Accounts",
                    style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _buildBankDetailRow("Account Title", "Negoo Technologies Pvt Ltd"),
                  _buildBankDetailRow("Bank", "Bank Alfalah (Corporate Banking)"),
                  _buildBankDetailRow("IBAN", "PK36ALFH0001829012398401"),
                  _buildBankDetailRow("JazzCash / EasyPaisa Till", "829301"),
                  _buildBankDetailRow(
                    "Partner Reference Code",
                    "NEG-HTL-${widget.userId.length >= 6 ? widget.userId.substring(0, 6).toUpperCase() : 'PARTNER'}",
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _showSnackBar("Settlement instructions & reference copied.", const Color(0xFFD4AF37));
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text("I HAVE REVIEWED DUES"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildBankDetailRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildDetailInvoiceRow(IconData icon, String header, String coreValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFD4AF37).withOpacity(0.7)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                coreValue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color badgeColor;
    String label;
    switch (status) {
      case 'confirmed':
        badgeColor = Colors.greenAccent;
        label = "CONFIRMED";
        break;
      case 'rejected':
        badgeColor = Colors.redAccent;
        label = "DECLINED";
        break;
      default:
        badgeColor = const Color(0xFFD4AF37);
        label = "PENDING";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withOpacity(0.02),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 44,
                color: const Color(0xFFD4AF37).withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "No Matching Bookings Found",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Incoming reservations, confirmed earnings, and Negoo fee splits will populate in this queue.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedgerRow(
    String desc,
    String value,
    Color textTheme, {
    bool isPrimary = false,
    IconData? icon,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
            ],
            Text(
              desc,
              style: TextStyle(
                color: isPrimary ? Colors.white : Colors.white60,
                fontWeight: isPrimary ? FontWeight.w900 : FontWeight.normal,
                fontSize: isPrimary ? 15 : 13,
              ),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            color: textTheme,
            fontWeight: FontWeight.bold,
            fontSize: isPrimary ? 18 : 14,
          ),
        ),
      ],
    );
  }
}
