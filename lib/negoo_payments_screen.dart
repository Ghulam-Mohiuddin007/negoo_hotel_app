import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:negoo_hotel_app/services/cache_service.dart';
import 'package:negoo_hotel_app/services/database_service.dart';
import 'package:negoo_hotel_app/services/toast_service.dart';

class NegooPaymentsScreen extends StatefulWidget {
  final String userId;
  const NegooPaymentsScreen({super.key, required this.userId});

  @override
  State<NegooPaymentsScreen> createState() => _NegooPaymentsScreenState();
}

class _NegooPaymentsScreenState extends State<NegooPaymentsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  String _activeFilter = 'all'; // 'all', 'unpaid', 'settled'

  /// Modal for hotel to submit referral number for Superadmin verification (One-time after check-out)
  void _showSubmitRemittanceDialog(Map<String, dynamic> booking) {
    final bookingId = booking['id'].toString();
    final uniqueId = BookingCacheService.formatUniqueBookingId(bookingId);
    final status = (booking['status'] ?? '').toString().toLowerCase();
    final bool isCheckedOut = status == 'checked_out' || booking['checked_out_at'] != null;
    final bool isSettled = DatabaseService.isCommissionSettled(booking);
    final existingRef = booking['remittance_ref']?.toString();
    final bool alreadySubmitted = existingRef != null && existingRef.trim().isNotEmpty;

    if (!isCheckedOut) {
      ToastService.warning("Referral number can only be submitted after the guest has checked out.");
      return;
    }

    if (alreadySubmitted) {
      ToastService.info("Referral number ($existingRef) has already been submitted for this booking.");
      return;
    }

    if (isSettled) {
      ToastService.success("Commission dues for this booking have already been cleared by Super Admin!");
      return;
    }

    final price = double.tryParse(booking['total_price']?.toString() ?? '0') ?? 0.0;
    final commission = price * 0.10;
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: Color(0xFFD4AF37), size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Send Referral No. to Super Admin",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_clock_rounded, color: Colors.purpleAccent, size: 12),
                    SizedBox(width: 4),
                    Text(
                      "ONE-TIME SUBMISSION AFTER CHECK-OUT",
                      style: TextStyle(color: Colors.purpleAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Booking: $uniqueId",
                style: const TextStyle(
                  color: Color(0xFFD4AF37),
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Guest: ${booking['full_name'] ?? 'Guest Traveler'}",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                "Negoo Commission Due: PKR ${commission.toStringAsFixed(0)}",
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Text(
                  "ℹ️ Note: Guest has checked out. Enter your bank transfer / JazzCash / EasyPaisa referral or transaction number. Super Admin will verify and clear your dues. This is a one-time submission.",
                  style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: "Referral / Transaction Number",
                  labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                  hintText: "e.g. REF-9482104 or Slip No.",
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 12),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final refCode = textController.text.trim();
              if (refCode.isEmpty) {
                ToastService.warning("Please enter a valid referral or transaction number.");
                return;
              }
              Navigator.pop(ctx);
              final success = await _databaseService.submitRemittanceVerification(
                bookingId,
                refCode,
                hotelId: widget.userId,
              );
              if (success) {
                ToastService.success("Referral number sent to Super Admin! Admin will audit & clear dues.");
                setState(() {});
              } else {
                ToastService.error("Failed to send referral number. Please try again.");
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Send to Super Admin", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _databaseService.fetchHotelBookings(widget.userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
            }

            final records = snapshot.data ?? [];

            // Calculate Negoo commission financials
            double totalGross = 0.0;
            double totalNegooCommission = 0.0;
            double settledCommission = 0.0;
            double unpaidNegooDues = 0.0;

            int unpaidCount = 0;
            int settledCount = 0;

            for (var b in records) {
              final status = b['status']?.toString().toLowerCase();
              if (status == 'confirmed' || status == 'checked_in' || status == 'checked_out') {
                final price = double.tryParse(b['total_price']?.toString() ?? '0') ?? 0.0;
                totalGross += price;
                final comm = price * 0.10; // Negoo 10% platform fee
                totalNegooCommission += comm;

                final isPaid = DatabaseService.isCommissionSettled(b);
                if (isPaid) {
                  settledCommission += comm;
                  settledCount++;
                } else {
                  unpaidNegooDues += comm;
                  unpaidCount++;
                }
              }
            }

            final hotelRetained = totalGross - totalNegooCommission;

            // Filter commission records
            List<Map<String, dynamic>> displayed = records.where((b) {
              final s = b['status']?.toString().toLowerCase();
              return s == 'confirmed' || s == 'checked_in' || s == 'checked_out';
            }).toList();

            if (_activeFilter == 'unpaid') {
              displayed = displayed.where((b) {
                return !DatabaseService.isCommissionSettled(b);
              }).toList();
            } else if (_activeFilter == 'settled') {
              displayed = displayed.where((b) {
                return DatabaseService.isCommissionSettled(b);
              }).toList();
            }

            return RefreshIndicator(
              color: const Color(0xFFD4AF37),
              onRefresh: () async => setState(() {}),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header - Wrapped in Expanded to completely prevent horizontal overflow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Negoo Platform Payments",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Platform Fee Matrix • Remittance Accounts • Superadmin Audit",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Color(0xFFD4AF37)),
                          tooltip: "Refresh Ledger",
                          onPressed: () => setState(() {}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Primary Negoo Financial Matrix Card
                    _buildNegooFinancialMatrixCard(
                      gross: totalGross,
                      commission: totalNegooCommission,
                      unpaidDues: unpaidNegooDues,
                      settled: settledCommission,
                      hotelNet: hotelRetained,
                    ),

                    const SizedBox(height: 20),

                    // Official Negoo Remittance Accounts Box
                    _buildRemittanceAccountsCard(),

                    const SizedBox(height: 24),

                    // Superadmin Notice Banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFD4AF37), size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Commission Policy: Only Negoo Corporate Superadmin can verify bank receipts and mark commission as PAID. Hotels submit payment references below.",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Commission Ledger Title & Filters
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Negoo Commission Ledger",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "${displayed.length} records",
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter chips - wrapped in SingleChildScrollView to prevent overflow
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', "All (${unpaidCount + settledCount})"),
                          const SizedBox(width: 8),
                          _buildFilterChip('unpaid', "Unpaid Dues ($unpaidCount)", badgeColor: Colors.amberAccent),
                          const SizedBox(width: 8),
                          _buildFilterChip('settled', "Settled by Admin ($settledCount)", badgeColor: Colors.greenAccent),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    if (displayed.isEmpty)
                      _buildEmptyLedgerState()
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: displayed.length,
                        itemBuilder: (context, index) {
                          final item = displayed[index];
                          return _buildCommissionLedgerRow(item);
                        },
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

  Widget _buildNegooFinancialMatrixCard({
    required double gross,
    required double commission,
    required double unpaidDues,
    required double settled,
    required double hotelNet,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildStatRow(
                  "Gross Booking Volume",
                  "PKR ${gross.toStringAsFixed(0)}",
                  Colors.white,
                  icon: Icons.payments_outlined,
                  isPrimary: true,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Colors.white10),
                ),
                _buildStatRow(
                  "Negoo Marketplace Cut (10%)",
                  "- PKR ${commission.toStringAsFixed(0)}",
                  Colors.redAccent.shade100,
                  icon: Icons.pie_chart_outline,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: Colors.white10),
                ),

                // Outstanding Dues Alert Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: unpaidDues > 0
                        ? Colors.amber.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: unpaidDues > 0
                          ? Colors.amber.withValues(alpha: 0.35)
                          : Colors.green.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              unpaidDues > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                              size: 20,
                              color: unpaidDues > 0 ? Colors.amber : Colors.greenAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "Unpaid Amount Due to Negoo",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    unpaidDues > 0 ? "Pending remittance to Negoo corporate" : "All platform fees cleared",
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "PKR ${unpaidDues.toStringAsFixed(0)}",
                        style: TextStyle(
                          color: unpaidDues > 0 ? Colors.amberAccent : Colors.greenAccent,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    "Hotel Net Retained Income",
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  "PKR ${hotelNet.toStringAsFixed(0)}",
                  style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.w900, fontSize: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemittanceAccountsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.account_balance, color: Color(0xFFD4AF37), size: 18),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Negoo Remittance Accounts",
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: "PK36ALFH0001829012398401"));
                  ToastService.info("Copied Negoo IBAN to clipboard");
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text("Copy IBAN", style: TextStyle(color: Colors.white70, fontSize: 10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBankRow("Account Title", "Negoo Technologies Pvt Ltd"),
          _buildBankRow("Bank", "Bank Alfalah (Corporate Banking)"),
          _buildBankRow("Corporate IBAN", "PK36ALFH0001829012398401"),
          _buildBankRow("JazzCash / EasyPaisa Till", "829301"),
          _buildBankRow("Partner Reference", "NEG-HTL-${widget.userId.length >= 6 ? widget.userId.substring(0, 6).toUpperCase() : 'PARTNER'}"),
        ],
      ),
    );
  }

  Widget _buildBankRow(String label, String val) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          Flexible(
            child: Text(
              val,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// Single Commission Ledger Row with Superadmin-controlled status
  Widget _buildCommissionLedgerRow(Map<String, dynamic> booking) {
    final rawId = booking['id']?.toString() ?? '';
    final uniqueId = BookingCacheService.formatUniqueBookingId(rawId);
    final price = double.tryParse(booking['total_price']?.toString() ?? '0') ?? 0.0;
    final negooFee = price * 0.10;
    final isSettled = DatabaseService.isCommissionSettled(booking);
    final bookingStatus = (booking['status'] ?? '').toString().toLowerCase();
    final bool isCheckedOut = bookingStatus == 'checked_out' || booking['checked_out_at'] != null;
    final remittanceRef = booking['remittance_ref']?.toString();
    final bool hasReferral = remittanceRef != null && remittanceRef.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSettled
              ? Colors.green.withValues(alpha: 0.25)
              : (hasReferral
                  ? Colors.cyan.withValues(alpha: 0.3)
                  : (isCheckedOut ? Colors.amber.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06))),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  uniqueId,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD4AF37),
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Superadmin Audited Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSettled
                      ? Colors.green.withValues(alpha: 0.15)
                      : (hasReferral
                          ? Colors.cyan.withValues(alpha: 0.15)
                          : (isCheckedOut
                              ? Colors.amber.withValues(alpha: 0.15)
                              : Colors.purple.withValues(alpha: 0.15))),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSettled
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : (hasReferral
                            ? Colors.cyanAccent.withValues(alpha: 0.3)
                            : (isCheckedOut
                                ? Colors.amber.withValues(alpha: 0.3)
                                : Colors.purpleAccent.withValues(alpha: 0.3))),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSettled
                          ? Icons.verified_rounded
                          : (hasReferral
                              ? Icons.send_and_archive_rounded
                              : (isCheckedOut ? Icons.hourglass_top_rounded : Icons.bed_outlined)),
                      size: 11,
                      color: isSettled
                          ? Colors.greenAccent
                          : (hasReferral
                              ? Colors.cyanAccent
                              : (isCheckedOut ? Colors.amberAccent : Colors.purpleAccent)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isSettled
                          ? "SETTLED BY SUPERADMIN"
                          : (hasReferral
                              ? "REFERRAL SENT • PENDING AUDIT"
                              : (isCheckedOut ? "AWAITING REFERRAL NUMBER" : "IN STAY (AWAITING CHECK-OUT)")),
                      style: TextStyle(
                        color: isSettled
                            ? Colors.greenAccent
                            : (hasReferral
                                ? Colors.cyanAccent
                                : (isCheckedOut ? Colors.amberAccent : Colors.purpleAccent)),
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            booking['full_name'] ?? 'Guest Traveler',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            "Gross: PKR ${price.toStringAsFixed(0)} • Negoo Cut (10%): PKR ${negooFee.toStringAsFixed(0)}",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
          ),
          const SizedBox(height: 10),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),

          // Superadmin verification status or submission action
          if (isSettled)
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hasReferral
                        ? "Cleared & Verified by Super Admin (Ref: $remittanceRef)"
                        : "Cleared & Verified by Negoo Corporate Super Admin",
                    style: TextStyle(
                      color: Colors.greenAccent.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            )
          else if (hasReferral)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_outlined, color: Colors.cyanAccent, size: 14),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          "Referral No: $remittanceRef (Sent to Super Admin)",
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "One-time lock 🔒",
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ),
              ],
            )
          else if (isCheckedOut)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "Guest checked out. Send referral number to admin:",
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.amberAccent.withValues(alpha: 0.8), fontSize: 11),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showSubmitRemittanceDialog(booking),
                  icon: const Icon(Icons.send_rounded, size: 12),
                  label: const Text("Send Referral No. (1-Time)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    "🔒 Referral number unlocks after guest check-out",
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    ToastService.info("Referral number can only be submitted after guest check-out.");
                  },
                  icon: const Icon(Icons.lock_outline, size: 12),
                  label: const Text("After Check-Out Only", style: TextStyle(fontSize: 10)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white38,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterKey, String label, {Color? badgeColor}) {
    final isSelected = _activeFilter == filterKey;
    return InkWell(
      onTap: () => setState(() => _activeFilter = filterKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4AF37) : const Color(0xFF141418),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD4AF37)
                : (badgeColor?.withValues(alpha: 0.3) ?? Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : (badgeColor ?? Colors.white70),
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String title, String val, Color color, {IconData? icon, bool isPrimary = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white38),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPrimary ? Colors.white : Colors.white60,
                    fontWeight: isPrimary ? FontWeight.w900 : FontWeight.normal,
                    fontSize: isPrimary ? 15 : 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          val,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: isPrimary ? 18 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyLedgerState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Text(
          "No commission entries found for this filter.",
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        ),
      ),
    );
  }
}
