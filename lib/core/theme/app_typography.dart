import 'package:flutter/material.dart';

/// Named typography tokens for AniStream's design system.
///
/// Deliberately carries only fontSize/fontWeight/letterSpacing/height —
/// NOT color. Too many of the text elements these tokens apply to switch
/// color based on live state (D-pad focus, mouse hover, status badges,
/// seeder-count thresholds) for a static theme color to help; baking
/// color into the token would just force a `.copyWith(color: ...)` at
/// every call site anyway, adding a layer without removing one. Color
/// stays applied inline via `AppPalette.*`.
///
/// Some tokens are shared across call sites whose *names* don't fully
/// describe every place they end up applied — e.g. `cardTitleCompact`
/// also drives `watchlist_screen.dart`'s tab labels, and
/// `cardTitleProminent` also drives its `_EmptyPane` title. The token
/// names haven't been revisited to match every use site; this is a known
/// naming gap, not a visual inconsistency.
///
/// Accessed via `context.appTypography` (see build_context_extensions.dart).
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  final TextStyle screenTitle;
  final TextStyle sectionTitle;
  final TextStyle dayShelfTitle;
  final TextStyle heroTitleDesktop;
  final TextStyle heroTitleMobile;
  final TextStyle cardTitleCompact;
  final TextStyle cardTitleProminent;
  final TextStyle tileSubtitle;
  final TextStyle metaLabel;
  final TextStyle badgeLabel;
  final TextStyle toastMessage;
  final TextStyle panelHeader;
  final TextStyle cardSummary;
  final TextStyle heroSynopsis;
  final TextStyle compactHeading;
  final TextStyle sectionEyebrow;

  const AppTypography({
    required this.screenTitle,
    required this.sectionTitle,
    required this.dayShelfTitle,
    required this.heroTitleDesktop,
    required this.heroTitleMobile,
    required this.cardTitleCompact,
    required this.cardTitleProminent,
    required this.tileSubtitle,
    required this.metaLabel,
    required this.badgeLabel,
    required this.toastMessage,
    required this.panelHeader,
    required this.cardSummary,
    required this.heroSynopsis,
    required this.compactHeading,
    required this.sectionEyebrow,
  });

  static const AppTypography standard = AppTypography(
    // scheduled_screen.dart's "Schedule" screen title.
    screenTitle: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
    ),
    // watchlist_screen.dart's "My Library" and search_results_screen.dart's
    // "Results for..." section titles.
    sectionTitle: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    // scheduled_screen.dart's day-shelf headers.
    dayShelfTitle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    // hero_banner.dart's title, desktop variant.
    heroTitleDesktop: TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.0,
    ),
    // hero_banner.dart's title, mobile variant.
    heroTitleMobile: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.0,
    ),
    // Compact card title, shared across torrent_tile.dart,
    // watchlist_cards.dart's WatchlistCard, anime_card.dart, and
    // calendar_card.dart, plus watchlist_screen.dart's tab labels — see
    // the class-level doc comment re: token-name drift on that last one.
    cardTitleCompact: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    // Larger-surface card title, shared across watchlist_cards.dart's
    // HeroCard and ListCard, and watchlist_screen.dart's `_EmptyPane`
    // title.
    cardTitleProminent: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    // settings_components.dart's SettingRowTile.subtitle,
    // settings_menu.dart's section descriptions, and
    // watchlist_cards.dart's HeroCard "Next: Episode N" caption.
    tileSubtitle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    // Status/score inline TextSpans across watchlist_cards.dart,
    // search_input.dart's result rows, scheduled_screen.dart's release
    // count, and hero_banner.dart's `_MetaChip`.
    metaLabel: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    // Badge/pill cluster: torrent_tile.dart's "RECOMMENDED" banner and
    // release-group/resolution pills, episode_tile.dart's "UP NEXT" tag,
    // watchlist_cards.dart's progress badge, anime_card.dart's
    // `_StatusBadge`, and calendar_card.dart's episode/time pills.
    badgeLabel: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    ),
    // glass_toast_content.dart's toast message.
    toastMessage: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    // navbar.dart's mobile "Menu" drawer header and settings_menu.dart's
    // "Settings" header.
    panelHeader: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    // watchlist_cards.dart's ListCard description summary — kept distinct
    // from heroSynopsis below (card summary vs. full-page synopsis).
    cardSummary: TextStyle(fontSize: 13, height: 1.4),
    // hero_banner.dart's multi-paragraph synopsis — kept distinct from
    // cardSummary above.
    heroSynopsis: TextStyle(fontSize: 14, height: 1.6),
    // 14/w600 cluster: settings_menu.dart's "Video Scaling Quality" /
    // "Hardware Decoding" / "Hardware Decoding (Android)" sub-headers,
    // settings_components.dart's SettingRowTile.title, and
    // search_input.dart's dropdown result-row title.
    compactHeading: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    // settings_components.dart's SettingsSection label — the small
    // uppercase "CONTENT PREFERENCES" / "PLAYBACK PREFERENCES" eyebrow
    // headers. Deliberately kept separate from badgeLabel despite both
    // being small/bold/spaced-out: badgeLabel's letter-spacing is less
    // than half of this token's, and collapsing them would visibly
    // compress the eyebrow's distinct spacing.
    sectionEyebrow: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );

  @override
  AppTypography copyWith({
    TextStyle? screenTitle,
    TextStyle? sectionTitle,
    TextStyle? dayShelfTitle,
    TextStyle? heroTitleDesktop,
    TextStyle? heroTitleMobile,
    TextStyle? cardTitleCompact,
    TextStyle? cardTitleProminent,
    TextStyle? tileSubtitle,
    TextStyle? metaLabel,
    TextStyle? badgeLabel,
    TextStyle? toastMessage,
    TextStyle? panelHeader,
    TextStyle? cardSummary,
    TextStyle? heroSynopsis,
    TextStyle? compactHeading,
    TextStyle? sectionEyebrow,
  }) {
    return AppTypography(
      screenTitle: screenTitle ?? this.screenTitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      dayShelfTitle: dayShelfTitle ?? this.dayShelfTitle,
      heroTitleDesktop: heroTitleDesktop ?? this.heroTitleDesktop,
      heroTitleMobile: heroTitleMobile ?? this.heroTitleMobile,
      cardTitleCompact: cardTitleCompact ?? this.cardTitleCompact,
      cardTitleProminent: cardTitleProminent ?? this.cardTitleProminent,
      tileSubtitle: tileSubtitle ?? this.tileSubtitle,
      metaLabel: metaLabel ?? this.metaLabel,
      badgeLabel: badgeLabel ?? this.badgeLabel,
      toastMessage: toastMessage ?? this.toastMessage,
      panelHeader: panelHeader ?? this.panelHeader,
      cardSummary: cardSummary ?? this.cardSummary,
      heroSynopsis: heroSynopsis ?? this.heroSynopsis,
      compactHeading: compactHeading ?? this.compactHeading,
      sectionEyebrow: sectionEyebrow ?? this.sectionEyebrow,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      screenTitle: TextStyle.lerp(screenTitle, other.screenTitle, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      dayShelfTitle: TextStyle.lerp(dayShelfTitle, other.dayShelfTitle, t)!,
      heroTitleDesktop: TextStyle.lerp(
        heroTitleDesktop,
        other.heroTitleDesktop,
        t,
      )!,
      heroTitleMobile: TextStyle.lerp(
        heroTitleMobile,
        other.heroTitleMobile,
        t,
      )!,
      cardTitleCompact: TextStyle.lerp(
        cardTitleCompact,
        other.cardTitleCompact,
        t,
      )!,
      cardTitleProminent: TextStyle.lerp(
        cardTitleProminent,
        other.cardTitleProminent,
        t,
      )!,
      tileSubtitle: TextStyle.lerp(tileSubtitle, other.tileSubtitle, t)!,
      metaLabel: TextStyle.lerp(metaLabel, other.metaLabel, t)!,
      badgeLabel: TextStyle.lerp(badgeLabel, other.badgeLabel, t)!,
      toastMessage: TextStyle.lerp(toastMessage, other.toastMessage, t)!,
      panelHeader: TextStyle.lerp(panelHeader, other.panelHeader, t)!,
      cardSummary: TextStyle.lerp(cardSummary, other.cardSummary, t)!,
      heroSynopsis: TextStyle.lerp(heroSynopsis, other.heroSynopsis, t)!,
      compactHeading: TextStyle.lerp(compactHeading, other.compactHeading, t)!,
      sectionEyebrow: TextStyle.lerp(sectionEyebrow, other.sectionEyebrow, t)!,
    );
  }
}
