import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/hover_focus_builder.dart';

/// A pill-shaped external link button — used for the AniList/MyAnimeList
/// row inside HeroBannerMetaBlock.
///
/// Uses a single, shared neutral/muted chrome (the same background/border
/// treatment `SettingsDropdown` uses elsewhere in the app:
/// `AppPalette.white` at low alpha, no per-instance tint). [color] — the
/// calling site's brand color (AniList blue, MyAnimeList navy) — drives
/// only the icon, which keeps the brand accent readable without three
/// differently-colored badges sitting in a row. Matches DESIGN.md §
/// 1.3's Apple-inspired-restraint principle: color should be meaningful,
/// not decorative — a status pill's color encodes real state (RELEASING
/// vs. FINISHED), while a link button's brand color doesn't encode
/// anything the icon and label don't already say, so it doesn't need to
/// dominate the whole chip.
class ExternalLinkButton extends StatelessWidget {
  final String label;
  final String url;
  final Color color;
  final IconData icon;

  const ExternalLinkButton({
    super.key,
    required this.label,
    required this.url,
    required this.color,
    this.icon = Icons.open_in_new_rounded,
  });

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      tooltip: url,
      onTap: _open,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppPalette.white.withValues(alpha: hovered ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppPalette.white.withValues(alpha: hovered ? 0.2 : 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: hovered ? AppPalette.textMain : AppPalette.textLight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
