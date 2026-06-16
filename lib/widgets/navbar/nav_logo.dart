import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';

class NavLogo extends StatefulWidget {
  final VoidCallback? onTap;
  const NavLogo({super.key, this.onTap});

  @override
  State<NavLogo> createState() => _NavLogoState();
}

class _NavLogoState extends State<NavLogo> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _hovered ? Colors.white : AppPalette.textMain,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
          child: const Text('AniStream'),
        ),
      ),
    );
  }
}
