import 'package:flutter/material.dart';
import '../../core/settings/settings_scope.dart';
import 'glass_toast_content.dart';

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

class _BottomToastWidget extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color iconColor;

  const _BottomToastWidget({
    required this.message,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return Align(
      alignment: Alignment.bottomCenter,
      child: GlassToastContent(
        message: message,
        icon: icon,
        iconColor: iconColor,
        uiPerformanceMode: uiPerformanceMode,
      ),
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
    // ── Uses SettingsScope directly instead of a locally-loaded
    // _uiPerformanceMode field — this widget is inserted via Overlay, so it
    // sits above whatever context called AppleTopSnackBar.show(context),
    // and SettingsScope is mounted at the app root, so it's always reachable
    // here. ──
    final uiPerformanceMode = SettingsScope.of(context).uiPerformanceMode;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + 24,
      left: 16,
      right: 16,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: SlideTransition(
            position: _offsetAnimation,
            child: Align(
              alignment: Alignment.topCenter,
              child: GlassToastContent(
                message: widget.message,
                icon: widget.icon,
                iconColor: widget.iconColor,
                uiPerformanceMode: uiPerformanceMode,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
