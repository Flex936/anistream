import 'package:flutter/material.dart';

/// Named text-style tokens: size, weight, letter spacing, and height only —
/// color stays inline via `AppPalette` because it varies with live state.
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
    screenTitle: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
    ),
    sectionTitle: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    ),
    dayShelfTitle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    heroTitleDesktop: TextStyle(
      fontSize: 48,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.0,
    ),
    heroTitleMobile: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1.0,
    ),
    cardTitleCompact: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    cardTitleProminent: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    tileSubtitle: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    metaLabel: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    badgeLabel: TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.5,
    ),
    toastMessage: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    panelHeader: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    cardSummary: TextStyle(fontSize: 13, height: 1.4),
    heroSynopsis: TextStyle(fontSize: 14, height: 1.6),
    compactHeading: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    // Separate from badgeLabel on purpose: its letter spacing is more than
    // double.
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