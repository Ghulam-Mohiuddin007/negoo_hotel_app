import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:negoo_hotel_app/main.dart';

enum ToastType { success, error, warning, info }

class ToastService {
  static OverlayEntry? _activeOverlay;
  static Timer? _dismissTimer;

  static void show(
    String msg, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    // 1. Safely call native Fluttertoast if available (silently ignores MissingPluginException)
    try {
      Fluttertoast.cancel();
      Fluttertoast.showToast(
        msg: msg,
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: _getBgColor(type),
        textColor: _getTextColor(type),
        fontSize: 13.5,
      );
    } catch (_) {}

    // 2. Pure Flutter Floating Overlay Toast (works 100% across all engines and platforms)
    try {
      final overlay = rootNavigatorKey.currentState?.overlay;
      if (overlay != null) {
        _dismissTimer?.cancel();
        _activeOverlay?.remove();
        _activeOverlay = null;

        _activeOverlay = OverlayEntry(
          builder: (context) => _LuxuryToastWidget(
            message: msg,
            type: type,
            onDismiss: () {
              _activeOverlay?.remove();
              _activeOverlay = null;
            },
          ),
        );

        overlay.insert(_activeOverlay!);
        _dismissTimer = Timer(duration, () {
          _activeOverlay?.remove();
          _activeOverlay = null;
        });
      }
    } catch (e) {
      debugPrint("Toast overlay notice: $e");
    }
  }

  static void success(String msg) => show(msg, type: ToastType.success);
  static void error(String msg) => show(msg, type: ToastType.error);
  static void warning(String msg) => show(msg, type: ToastType.warning);
  static void info(String msg) => show(msg, type: ToastType.info);

  static Color _getBgColor(ToastType type) {
    switch (type) {
      case ToastType.success:
        return const Color(0xFF1B5E20);
      case ToastType.error:
        return const Color(0xFFB71C1C);
      case ToastType.warning:
        return const Color(0xFFE65100);
      case ToastType.info:
        return const Color(0xFF141418);
    }
  }

  static Color _getTextColor(ToastType type) {
    switch (type) {
      case ToastType.info:
        return const Color(0xFFD4AF37);
      default:
        return Colors.white;
    }
  }
}

class _LuxuryToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final VoidCallback onDismiss;

  const _LuxuryToastWidget({
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_LuxuryToastWidget> createState() => _LuxuryToastWidgetState();
}

class _LuxuryToastWidgetState extends State<_LuxuryToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.type) {
      case ToastType.success:
        return Colors.greenAccent;
      case ToastType.error:
        return Colors.redAccent;
      case ToastType.warning:
        return Colors.amberAccent;
      case ToastType.info:
        return const Color(0xFFD4AF37);
    }
  }

  IconData get _icon {
    switch (widget.type) {
      case ToastType.success:
        return Icons.check_circle_rounded;
      case ToastType.error:
        return Icons.error_rounded;
      case ToastType.warning:
        return Icons.warning_amber_rounded;
      case ToastType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 110,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Material(
              color: Colors.transparent,
              child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF141418).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _accentColor.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon, color: _accentColor, size: 20),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
