/// Returns [Duration.zero] when [uiPerformanceMode] is true, otherwise
/// [normal].
///
/// Centralizes the "skip this animation's transition entirely on weak
/// hardware" decision so it isn't re-implemented (or forgotten) per widget.
/// An `Animated*` widget given a zero duration still applies its end state
/// immediately on the very next frame — no interpolation, no extra frames,
/// no offscreen compositing across the transition — which is exactly what
/// Performant mode wants for opacity/slide/scale/blur effects that would
/// otherwise force a `saveLayer` on every frame of the animation.
Duration perfDuration(bool uiPerformanceMode, Duration normal) =>
    uiPerformanceMode ? Duration.zero : normal;
