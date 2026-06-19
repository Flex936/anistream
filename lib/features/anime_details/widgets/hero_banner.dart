import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../data/anilist/models/anime.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/app_network_image.dart';

// ── Private Formatting Helpers ──
String _stripHtml(String? html) {
  if (html == null || html.isEmpty) return 'No synopsis available.';
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

Color _statusColor(String? s) => switch (s) {
      'RELEASING' => AppPalette.statusReleasing,
      'FINISHED' => AppPalette.statusFinished,
      'CANCELLED' => AppPalette.statusCancelled,
      'HIATUS' => AppPalette.statusHiatus,
      _ => AppPalette.statusDefault,
    };

String _formatStatus(String? s) => (s ?? 'UNKNOWN').replaceAll('_', ' ');

// ════════════════════════════════════════════════════════════════════════════
//  HeroBanner
// ════════════════════════════════════════════════════════════════════════════

class HeroBanner extends StatelessWidget {
  final Anime anime;
  final VoidCallback? onBack;

  const HeroBanner({super.key, required this.anime, this.onBack});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return isMobile ? _buildMobileLayout() : _buildDesktopLayout();
  }

  // ── 1. Desktop Layout (Classic Stacked Banner) ──
  Widget _buildDesktopLayout() {
    final bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;
    final posterUrl = anime.coverImage?.extraLarge;

    return SizedBox(
      width: double.infinity,
      height: 600,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bannerUrl != null) AppNetworkImage(url: bannerUrl),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppPalette.base.withValues(alpha: 0.1),
                  AppPalette.base.withValues(alpha: 0.7),
                  AppPalette.base,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          Positioned(
            top: 96,
            left: 48,
            child: _FloatingNavBar(onBack: onBack),
          ),

          Positioned(
            bottom: 24,
            left: 48,
            right: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (posterUrl != null) _PosterImage(url: posterUrl),
                const SizedBox(width: 48),
                Expanded(child: _AnimeTextInfo(anime: anime, isMobile: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 2. Mobile Layout (Safe Column Layout) ──
  Widget _buildMobileLayout() {
    final bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;
    final posterUrl = anime.coverImage?.extraLarge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top section with Banner Background and Back Button
        SizedBox(
          height: 250,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bannerUrl != null) 
                AppNetworkImage(url: bannerUrl)
              else 
                const ColoredBox(color: AppPalette.surface),
              
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppPalette.base.withValues(alpha: 0.3),
                      AppPalette.base.withValues(alpha: 0.9),
                      AppPalette.base,
                    ],
                  ),
                ),
              ),
              
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24, left: 16),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: _FloatingNavBar(onBack: onBack),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom section with Poster and Text
        Transform.translate(
          offset: const Offset(0, -80), // Pulls the content up over the banner gradient
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (posterUrl != null) _PosterImage(url: posterUrl),
                const SizedBox(height: 32),
                _AnimeTextInfo(anime: anime, isMobile: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PosterImage extends StatelessWidget {
  final String url;
  const _PosterImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 330,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppPalette.black.withValues(alpha: 0.6),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AppNetworkImage(url: url),
      ),
    );
  }
}

class _AnimeTextInfo extends StatelessWidget {
  final Anime anime;
  final bool isMobile;
  const _AnimeTextInfo({required this.anime, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          anime.title.display,
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: AppPalette.textMain,
            fontSize: isMobile ? 32 : 48,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -1.0,
          ),
        ),
        if (anime.title.english != null && anime.title.english != anime.title.romaji) ...[
          const SizedBox(height: 8),
          Text(
            anime.title.english!,
            textAlign: isMobile ? TextAlign.center : TextAlign.left,
            style: const TextStyle(color: AppPalette.textMuted, fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _MetaChip(label: _formatStatus(anime.status), color: _statusColor(anime.status)),
            if (anime.episodes != null) _MetaChip(label: '${anime.episodes} Episodes', color: AppPalette.textLight),
            if (anime.averageScore != null)
              _MetaChip(label: '★ ${(anime.averageScore! / 10).toStringAsFixed(1)} Score', color: AppPalette.accent),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          _stripHtml(anime.description),
          maxLines: isMobile ? 5 : 4,
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppPalette.textMuted, fontSize: 14, height: 1.6),
        ),
      ],
    );
  }
}

class _FloatingNavBar extends StatefulWidget {
  final VoidCallback? onBack;
  const _FloatingNavBar({this.onBack});

  @override
  State<_FloatingNavBar> createState() => _FloatingNavBarState();
}

class _FloatingNavBarState extends State<_FloatingNavBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (widget.onBack != null) {
            widget.onBack!();
          } else {
            Navigator.maybePop(context);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _hovered ? AppPalette.white.withValues(alpha: 0.15) : AppPalette.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSlide(
                    offset: _hovered ? const Offset(-0.15, 0) : Offset.zero,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.arrow_back_rounded, size: 18, color: AppPalette.textMain),
                  ),
                  const SizedBox(width: 8),
                  const Text('Back', style: TextStyle(color: AppPalette.textMain, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}