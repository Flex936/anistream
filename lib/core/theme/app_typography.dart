import 'package:flutter/material.dart';

/// Named typography tokens for AniStream's design system.
///
/// Deliberately carries only fontSize/fontWeight/letterSpacing/height —
/// NOT color. Too many of the text elements these tokens replace switch
/// color based on live state (D-pad focus, mouse hover, status badges,
/// seeder-count thresholds) for a static theme color to help; baking
/// color into the token would just force a `.copyWith(color: ...)` at
/// every call site anyway, adding a layer without removing one. Color
/// stays applied inline via `AppPalette.*`, exactly as before this
/// migration.
///
/// Several fields below are deliberate CONVERGENCES of previously
/// near-duplicate literals scattered across the codebase (see each
/// field's comment for the specific call sites and values it replaces) —
///
/// Some tokens are also reused across call sites whose *names* don't
/// quite describe every place they end up applied (e.g.
/// `cardTitleCompact` also drives `watchlist_screen.dart`'s tab labels,
/// `cardTitleProminent` also drives its `_EmptyPane` title) — sizes/
/// weights matched closely enough to converge, but the token names
/// haven't been revisited to match. Left as a known follow-up rather
/// than renamed mid-pass.
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
    // scheduled_screen.dart "Schedule" — exact match, no convergence.
    screenTitle: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
    ),
    // watchlist_screen.dart "My Library", search_results_screen.dart
    // "Results for..." — exact match, no convergence.
    sectionTitle: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    // scheduled_screen.dart day-shelf headers — exact match.
    dayShelfTitle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    // hero_banner.dart title, desktop variant — exact match.
    heroTitleDesktop: TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.0,
    ),
    // hero_banner.dart title, mobile variant — exact match.
    heroTitleMobile: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.0,
    ),
    // ── torrent_tile.dart (was 13/w500/h1.4),
    // watchlist_cards.dart WatchlistCard (was 13/w600/h1.35),
    // anime_card.dart (was 13/w500/h1.35), calendar_card.dart (was
    // 12/w600/h1.2) — four near-duplicate "compact card title" variants
    // collapsed into one. Also reused for
    // watchlist_screen.dart's tab labels (13/w600 exact numeric match) —
    // see the class-level doc comment re: token-name drift. ──
    cardTitleCompact: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    // ── watchlist_cards.dart HeroCard (was
    // 14/w700), watchlist_cards.dart ListCard (was 16/bold) — the two
    // "prominent" (larger-surface) card titles collapsed into one. Also
    // reused for watchlist_screen.dart's _EmptyPane title
    // (was 16/w600 — one step lighter than this token's w700). ──
    cardTitleProminent: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    // settings_components.dart SettingRowTile.subtitle,
    // settings_menu.dart section descriptions — exact match.
    tileSubtitle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    // Status/score inline TextSpans across watchlist_cards.dart,
    // search_input.dart result rows. Also applied to
    // hero_banner.dart's _MetaChip (was 12/w700 — one step heavier than
    // this token's w600; the only other nearby candidate was badgeLabel,
    // whose fontSize (10) was a worse fit).
    metaLabel: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    // ── torrent_tile.dart "RECOMMENDED" banner
    // (was 10/w800/1.0 spacing), torrent_tile.dart _Pill (was
    // 10/w700/0.3 spacing), episode_tile.dart "UP NEXT" (was 9/w800/0.5
    // spacing), plus WatchlistCard's progress badge,
    // anime_card._StatusBadge, and calendar_card's episode/time pills —
    // a wider badge/pill cluster than originally scoped, all
    // collapsed into one. ──
    badgeLabel: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    ),
    // glass_toast_content.dart — exact match.
    toastMessage: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    // ── navbar.dart mobile "Menu" drawer header
    // (was 24/bold/-0.5) and settings_menu.dart "Settings" header (was
    // 26/bold/-0.5) — standardized on 24 per the leaner option. ──
    panelHeader: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    // watchlist_cards.dart ListCard description summary — kept distinct
    // from heroSynopsis below (different context: card summary vs.
    // full-page synopsis), not force-merged.
    cardSummary: TextStyle(fontSize: 13, height: 1.4),
    // hero_banner.dart multi-paragraph synopsis — kept distinct from
    // cardSummary above.
    heroSynopsis: TextStyle(fontSize: 14, height: 1.6),
    // ── Recurring 14/w600 cluster that wasn't an
    // original scope: settings_menu.dart's "Video Scaling Quality" /
    // "Hardware Decoding" / "Hardware Decoding (Android)" sub-headers,
    // settings_components.dart's SettingRowTile.title, and
    // search_input.dart's dropdown result-row title — all exact matches,
    // zero visual delta at every call site. ──
    compactHeading: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    // ── settings_components.dart's SettingsSection
    // label — the small uppercase "CONTENT PREFERENCES" / "PLAYBACK
    // PREFERENCES" eyebrow headers. Exact match, zero visual delta.
    // Deliberately kept separate from badgeLabel despite both being
    // small/bold/spaced-out: badgeLabel's spacing (0.5) is less than
    // half of this token's (1.2), and collapsing them would have
    // visibly compressed the eyebrow's distinct letter-spacing. ──
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
