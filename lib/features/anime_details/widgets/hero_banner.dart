import 'package:flutter/material.dart';

import '../../../data/anilist/models/anime.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/app_network_image.dart';
import '../../../shared/widgets/hover_focus_builder.dart';
import '../../../shared/widgets/frosted_container.dart';
import '../../../shared/utils/anime_status_style.dart';
import '../../../shared/utils/html_utils.dart';
import './external_link_buttons.dart';

class HeroBanner extends StatelessWidget {
  final Anime anime;
  final VoidCallback? onBack;
  final bool uiPerformanceMode;

  const HeroBanner({
    super.key,
    required this.anime,
    this.onBack,
    this.uiPerformanceMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    return isMobile ? _buildMobileLayout() : _buildDesktopLayout();
  }

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
            child: _FloatingNavBar(
              onBack: onBack,
              uiPerformanceMode: uiPerformanceMode,
            ),
          ),

          Positioned(
            bottom: 24,
            left: 48,
            right: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (posterUrl != null)
                  _PosterImage(
                    url: posterUrl,
                    uiPerformanceMode: uiPerformanceMode,
                  ),
                const SizedBox(width: 48),
                Expanded(child: _AnimeTextInfo(anime: anime, isMobile: false)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    final bannerUrl = anime.bannerImage ?? anime.coverImage?.extraLarge;
    final posterUrl = anime.coverImage?.extraLarge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                    child: _FloatingNavBar(
                      onBack: onBack,
                      uiPerformanceMode: uiPerformanceMode,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, -80, 24, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (posterUrl != null)
                _PosterImage(
                  url: posterUrl,
                  uiPerformanceMode: uiPerformanceMode,
                ),
              const SizedBox(height: 32),
              _AnimeTextInfo(anime: anime, isMobile: true),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterImage extends StatelessWidget {
  final String url;
  final bool uiPerformanceMode;
  const _PosterImage({required this.url, this.uiPerformanceMode = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 330,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: uiPerformanceMode
            ? null
            : [
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
      crossAxisAlignment: isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
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
        if (anime.title.english != null &&
            anime.title.english != anime.title.romaji) ...[
          const SizedBox(height: 8),
          Text(
            anime.title.english!,
            textAlign: isMobile ? TextAlign.center : TextAlign.left,
            style: const TextStyle(
              color: AppPalette.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: [
            _MetaChip(
              label: anime.status?.statusLabel ?? 'UNKNOWN',
              color: anime.status?.statusColor ?? AppPalette.statusDefault,
            ),
            if (anime.episodes != null)
              _MetaChip(
                label: '${anime.episodes} Episodes',
                color: AppPalette.textLight,
              ),
            if (anime.averageScore != null)
              _MetaChip(
                label:
                    '★ ${(anime.averageScore! / 10).toStringAsFixed(1)} Score',
                color: AppPalette.accent,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: [
            ExternalLinkButton(
              label: 'AniList',
              url: 'https://anilist.co/anime/${anime.id}',
              color: const Color(0xFF3DB4F2),
            ),
            if (anime.idMal != null)
              ExternalLinkButton(
                label: 'MyAnimeList',
                url: 'https://myanimelist.net/anime/${anime.idMal}',
                color: const Color(0xFF2E51A2),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          // ── Was a locally-defined _stripHtml; now shared with
          // watchlist_cards.dart via stripAnilistHtml. This screen wants
          // multi-paragraph line breaks preserved, unlike the card summary. ──
          stripAnilistHtml(anime.description, preserveLineBreaks: true),
          maxLines: isMobile ? 5 : 4,
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppPalette.textMuted,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final VoidCallback? onBack;
  final bool uiPerformanceMode;
  const _FloatingNavBar({this.onBack, this.uiPerformanceMode = false});

  @override
  Widget build(BuildContext context) {
    return HoverFocusBuilder(
      onTap: () {
        if (onBack != null) {
          onBack!();
        } else {
          Navigator.maybePop(context);
        }
      },
      builder: (context, hovered) {
        final content = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: hovered
                ? AppPalette.white.withValues(alpha: 0.15)
                : AppPalette.black.withValues(
                    alpha: uiPerformanceMode ? 0.8 : 0.4,
                  ),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppPalette.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSlide(
                offset: hovered ? const Offset(-0.15, 0) : Offset.zero,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: AppPalette.textMain,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Back',
                style: TextStyle(
                  color: AppPalette.textMain,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );

        return FrostedContainer(
          uiPerformanceMode: uiPerformanceMode,
          sigma: 12,
          borderRadius: BorderRadius.circular(30),
          child: content,
        );
      },
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
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
