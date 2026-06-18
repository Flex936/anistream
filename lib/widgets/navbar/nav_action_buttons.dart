import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';

class NavIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const NavIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  State<NavIconButton> createState() => _NavIconButtonState();
}

class _NavIconButtonState extends State<NavIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            // Minimum comfortable touch target for mobile
            width: 44,
            height: 44,
            color: AppPalette.transparent, // Ensures the entire box is clickable
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              color: _hovered ? AppPalette.primary : AppPalette.textMuted,
              size: 22, // Slightly larger icon
            ),
          ),
        ),
      ),
    );
  }
}

class UserButton extends StatefulWidget {
  final bool isLoggedIn;
  final VoidCallback? onPressed;

  const UserButton({super.key, required this.isLoggedIn, this.onPressed});

  @override
  State<UserButton> createState() => _UserButtonState();
}

class _UserButtonState extends State<UserButton> {
  bool _hovered = false;

  Color get _iconColor {
    if (widget.isLoggedIn) {
      return _hovered ? AppPalette.statusCancelled : AppPalette.statusReleasing;
    }
    return _hovered ? AppPalette.textMain : AppPalette.textMuted;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.isLoggedIn ? 'Log out of AniList' : 'Log in to AniList',
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 44,
            height: 44,
            color: AppPalette.transparent,
            alignment: Alignment.center,
            child: Icon(
              Icons.person_outline_rounded,
              color: _iconColor,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class WindowButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color? hoverColor;
  final VoidCallback? onPressed;

  const WindowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.hoverColor,
    this.onPressed,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 44,
            height: 44,
            color: AppPalette.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              color: _hovered
                  ? (widget.hoverColor ?? AppPalette.textMain)
                  : AppPalette.textMuted,
              size: 20, // Keep window controls slightly smaller and sharper
            ),
          ),
        ),
      ),
    );
  }
}