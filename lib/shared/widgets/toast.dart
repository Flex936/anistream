import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_palette.dart';
import '../../core/settings/settings_service.dart';

// ── Apple-Style Premium Glass Toast (Bottom) ──

class AppleSnackBar {
  static void show({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 40, left: 16, right: 16),
        content: _BottomToastWidget(
          message: message,
          icon: icon,
          iconColor: iconColor,
        ),
      ),
    );
  }
}

class _BottomToastWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color iconColor;

  const _BottomToastWidget({
    required this.message,
    required this.icon,
    required this.iconColor,
  });

  @override
  State<_BottomToastWidget> createState() => _BottomToastWidgetState();
}

class _BottomToastWidgetState extends State<_BottomToastWidget> {
  bool _uiPerformanceMode = false;

  @override
  void initState() {
    super.initState();
    SettingsService().load().then((s) {
      if (mounted) setState(() => _uiPerformanceMode = s.uiPerformanceMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.surface.withValues(
          alpha: _uiPerformanceMode ? 0.98 : 0.75,
        ),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: AppPalette.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: _uiPerformanceMode
            ? null
            : [
                // ── Drop shadow conditionally ──
                BoxShadow(
                  color: AppPalette.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, color: widget.iconColor, size: 20),
          const SizedBox(width: 10),
          Text(
            widget.message,
            style: const TextStyle(
              color: AppPalette.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    // ── Conditional Blur ──
    if (!_uiPerformanceMode) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: content,
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: ClipRRect(borderRadius: BorderRadius.circular(50), child: content),
    );
  }
}

// ── Apple-Style Premium Glass Toast (Top Overlay for Theater) ──

class AppleTopSnackBar {
  static void show({
    required BuildContext context,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _TopToastWidget(
        message: message,
        icon: icon,
        iconColor: iconColor,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );

    overlay.insert(entry);
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.icon,
    required this.iconColor,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  bool _uiPerformanceMode = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    SettingsService().load().then((s) {
      if (mounted) setState(() => _uiPerformanceMode = s.uiPerformanceMode);
    });

    _controller.forward();

    Future.delayed(const Duration(seconds: 4), () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.surface.withValues(
          alpha: _uiPerformanceMode ? 0.98 : 0.75,
        ),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: AppPalette.white.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: _uiPerformanceMode
            ? null
            : [
                // ── Drop shadow conditionally ──
                BoxShadow(
                  color: AppPalette.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, color: widget.iconColor, size: 20),
          const SizedBox(width: 10),
          Text(
            widget.message,
            style: const TextStyle(
              color: AppPalette.textMain,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    // ── Conditional Blur ──
    if (!_uiPerformanceMode) {
      content = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: content,
      );
    }

    return Positioned(
      top: MediaQuery.sizeOf(context).top + 24,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: SlideTransition(
            position: _offsetAnimation,
            child: Align(
              alignment: Alignment.topCenter,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
