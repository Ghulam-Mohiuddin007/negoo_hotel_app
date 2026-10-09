import 'dart:ui';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
  }

  Future<void> _updateBookingStatus(
    String bookingId,
    String targetStatus,
  ) async {
    setState(() => _isActionLoading = true);
    try {
      await _supabase
          .from('bookings')
          .update({'status': targetStatus})
          .eq('id', bookingId);

      if (!mounted) return;
      Navigator.pop(
        context,
      ); // Close the detail popup menu on confirmation completion

      _showSnackBar(
        targetStatus == 'confirmed'
            ? "Reservation successfully authorized!"
            : "Reservation declined and slot released.",
        targetStatus == 'confirmed'
            ? Colors.green.shade800
            : Colors.orange.shade800,
      );
    } catch (e) {
      _showSnackBar("Execution failure: $e", Colors.redAccent);
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
      // 1. FIXED FOR ACCURACY: Force Postgrest to perform a hard PostgreSQL inner join filter match execution sequence
      // The select query filters the records so that ONLY bookings matching your current user ID are returned from the server.
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

        // 2. EXTRA PROTECTION LAYER: Filter arrays safely on the device side to clean out empty references
        final historicalRecords = (futureSnapshot.data ?? []).where((booking) {
          final roomData = booking['rooms'] as Map<String, dynamic>?;
          return roomData != null && roomData['hotel_id'] == widget.userId;
        }).toList();

        if (historicalRecords.isEmpty) return _buildEmptyState();

        // Perform financial statement math operations
        double grossSum = 0.0;
        for (var tx in historicalRecords) {
          if (tx['status'] == 'confirmed') {
            grossSum += (double.tryParse(tx['total_price'].toString()) ?? 0.0);
          }
        }

        double marketCommissionCut = grossSum * 0.10;
        double netRetainedBalance = grossSum - marketCommissionCut;

        return RefreshIndicator(
          color: const Color(0xFFD4AF37),
          backgroundColor: const Color(0xFF121214),
          onRefresh: () async => setState(() {}),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
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
                  "Real-time revenue statements minus automated system cuts.",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),

                _buildPremiumMetricsCard(
                  grossSum,
                  marketCommissionCut,
                  netRetainedBalance,
                ),

                const SizedBox(height: 35),
                const Text(
                  "Reservation Management Queue",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 16),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: historicalRecords.length,
                  itemBuilder: (context, index) {
                    final booking = historicalRecords[index];
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

  Widget _buildPremiumMetricsCard(double gross, double cut, double net) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                _buildLedgerRow(
                  "Confirmed Monthly Gross",
                  "PKR ${gross.toStringAsFixed(0)}",
                  Colors.white70,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(color: Colors.white10, height: 1),
                ),
                _buildLedgerRow(
                  "Negoo Marketplace Fee (10%)",
                  "- PKR ${cut.toStringAsFixed(0)}",
                  Colors.redAccent.withOpacity(0.8),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.08),
              ),
            ),
            child: _buildLedgerRow(
              "Net Disbursable Balance",
              "PKR ${net.toStringAsFixed(0)}",
              const Color(0xFFD4AF37),
              isImportant: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingItemRow(Map<String, dynamic> booking) {
    final roomData = booking['rooms'] as Map<String, dynamic>?;
    final String roomDesignation = roomData?['room_type'] ?? 'Standard Suite';
    final String status = booking['status'] ?? 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _displayBookingDetailsSheet(booking, roomDesignation),
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.01),
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
              const SizedBox(width: 16),
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
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildStatusBadge(status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _displayBookingDetailsSheet(
    Map<String, dynamic> booking,
    String roomType,
  ) {
    final String currentStatus = booking['status'] ?? 'pending';

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
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
              const SizedBox(height: 24),

              _buildDetailInvoiceRow(
                Icons.person_outline_rounded,
                "Lead Client Guest",
                booking['full_name'] ?? 'N/A',
              ),
              _buildDetailInvoiceRow(
                Icons.phone_enabled_outlined,
                "Contact Number",
                booking['phone'] ?? 'N/A',
              ),
              _buildDetailInvoiceRow(
                Icons.badge_outlined,
                "National CNIC Identifier",
                booking['cnic'] ?? 'N/A',
              ),
              _buildDetailInvoiceRow(
                Icons.meeting_room_outlined,
                "Suite Allocation",
                roomType,
              ),
              _buildDetailInvoiceRow(
                Icons.people_outline_rounded,
                "Total Guests",
                "${booking['guest_count'] ?? 1} Persons Allotted",
              ),
              _buildDetailInvoiceRow(
                Icons.date_range_outlined,
                "Stay Duration Timeline",
                "${booking['stay_from']} to ${booking['stay_to']}",
              ),
              _buildDetailInvoiceRow(
                Icons.payment_rounded,
                "Stipulated Payment Method",
                (booking['payment_method'] ?? 'cash').toString().toUpperCase(),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(color: Colors.white10),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Total Deal Payout",
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                  Text(
                    "PKR ${booking['total_price']}",
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              if (currentStatus == 'pending')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isActionLoading
                            ? null
                            : () => _updateBookingStatus(
                                booking['id'].toString(),
                                'rejected',
                              ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          "DECLINE OFFER",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isActionLoading
                            ? null
                            : () => _updateBookingStatus(
                                booking['id'].toString(),
                                'confirmed',
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: _isActionLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                "CONFIRM ACCESS",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: Colors.white38,
                    ),
                    label: const Text(
                      "RETURN TO LEDGER",
                      style: TextStyle(
                        color: Colors.white60,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

  Widget _buildDetailInvoiceRow(
    IconData icon,
    String header,
    String coreValue,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFD4AF37).withOpacity(0.6)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                header,
                style: const TextStyle(
                  color: Colors.white24,
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
        color: badgeColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.15)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFD4AF37).withOpacity(0.01),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 44,
                color: const Color(0xFFD4AF37).withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "No Transaction History",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Incoming room checkout logs and platform commissions will dynamically sync across this terminal ledger.",
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
    bool isImportant = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          desc,
          style: TextStyle(
            color: isImportant ? Colors.white : Colors.white54,
            fontWeight: isImportant ? FontWeight.w900 : FontWeight.normal,
            fontSize: isImportant ? 15 : 13,
            letterSpacing: isImportant ? -0.2 : 0,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: textTheme,
            fontWeight: FontWeight.bold,
            fontSize: isImportant ? 18 : 14,
          ),
        ),
      ],
    );
  }
}
