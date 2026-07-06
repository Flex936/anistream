import '../../core/extensions/build_context_extensions.dart';

/// Column counts for portrait/poster-style grids (~0.5 aspect ratio).
/// Replaces `WatchlistScreen._verticalColumns` and
/// `SearchResultsScreen._animeGridColumns`, which used identical values.
int verticalGridColumns(double width) {
  if (width < Breakpoints.mobile) return 2;
  if (width < Breakpoints.tablet) return 3;
  if (width < Breakpoints.desktop) return 4;
  if (width < Breakpoints.wide) return 5;
  return 6;
}

/// Column counts for landscape/hero-style grids (~1.77 aspect ratio).
/// Replaces `WatchlistScreen._landscapeColumns`.
int landscapeGridColumns(double width) {
  if (width < Breakpoints.mobile) return 1;
  if (width < Breakpoints.tablet) return 2;
  if (width < Breakpoints.desktop) return 3;
  if (width < Breakpoints.wide) return 4;
  return 5;
}
