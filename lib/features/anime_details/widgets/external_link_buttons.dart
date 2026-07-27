import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/hover_focus_builder.dart';

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
          color: color.withValues(alpha: hovered ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: hovered ? 0.7 : 0.3),
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
                color: color,
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
