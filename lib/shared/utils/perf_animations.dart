/// Returns [Duration.zero] under [uiPerformanceMode], so an `Animated*` widget
/// snaps to its end state with no interpolation or `saveLayer` (DESIGN.md § 2).
Duration perfDuration(bool uiPerformanceMode, Duration normal) =>
    uiPerformanceMode ? Duration.zero : normal;