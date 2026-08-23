import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/app_segmented_control.dart';
import '../../../shared/widgets/frosted_container.dart';

class SearchFilterPanel extends StatefulWidget {
  final int initialMinScore;
  final String initialStatus;
  final double initialYear;
  final void Function(int minScore, String status, double year) onApply;
  final bool uiPerformanceMode;

  const SearchFilterPanel({
    super.key,
    required this.initialMinScore,
    required this.initialStatus,
    required this.initialYear,
    required this.onApply,
    this.uiPerformanceMode = false,
  });

  @override
  State<SearchFilterPanel> createState() => _SearchFilterPanelState();
}

class _SearchFilterPanelState extends State<SearchFilterPanel> {
  late int _minScore;
  late String _selectedStatus;
  late double _selectedYear;

  // Bug fix: Material's stock Slider binds
  // ALL FOUR arrow keys internally via its own Shortcuts/Actions
  // (Up/Right = increase, Down/Left = decrease) and always returns
  // `handled` — there's no boundary case where it lets an event bubble,
  // unlike TextField's cursor-position-gated key handling. That made
  // Up/Down permanently "stick" on whichever slider first received
  // keyboard/D-Pad focus, since no ancestor Focus.onKeyEvent ever got a
  // turn — the Slider itself was the focused node, not an ancestor of it.
  // `Seekbar` (the theater scrubber) sidesteps this entirely by not using
  // Slider at all — a fully custom Focus + GestureDetector with
  // Left/Right-only key handling. Rebuilding two sliders from scratch for
  // this simpler panel isn't warranted, so instead: each Slider gets its
  // own FocusNode with canRequestFocus: false, removing it from
  // keyboard/D-Pad focus entirely (mouse/touch drag is untouched — that's
  // pointer-based, not focus-based). A thin outer Focus becomes the real
  // reachable target, handling Left/Right locally and ignoring everything
  // else so Up/Down bubble past this slider instead of being swallowed —
  // same shape as AppSegmentedControl's own key handler
  // (shared/widgets/app_segmented_control.dart).
  late final FocusNode _minScoreFocusNode;
  late final FocusNode _minScoreSliderInternalFocusNode;
  late final FocusNode _yearFocusNode;
  late final FocusNode _yearSliderInternalFocusNode;

  static const List<String> _statusOptions = ['ANY', 'RELEASING', 'FINISHED'];

  @override
  void initState() {
    super.initState();
    _minScore = widget.initialMinScore;
    _selectedStatus = widget.initialStatus;
    _selectedYear = widget.initialYear;

    _minScoreFocusNode = FocusNode(debugLabel: 'MinScoreSlider')
      ..onKeyEvent = _handleMinScoreKey;
    _minScoreSliderInternalFocusNode = FocusNode(
      debugLabel: 'MinScoreSliderInternal',
      canRequestFocus: false,
      skipTraversal: true,
    );

    _yearFocusNode = FocusNode(debugLabel: 'YearSlider')
      ..onKeyEvent = _handleYearKey;
    _yearSliderInternalFocusNode = FocusNode(
      debugLabel: 'YearSliderInternal',
      canRequestFocus: false,
      skipTraversal: true,
    );
  }

  @override
  void dispose() {
    _minScoreFocusNode.dispose();
    _minScoreSliderInternalFocusNode.dispose();
    _yearFocusNode.dispose();
    _yearSliderInternalFocusNode.dispose();
    super.dispose();
  }

  // Left/Right nudge the score by 1, clamped to [0, 100] — the same
  // step Slider's own divisions: 100 would produce via drag. Up/Down are
  // ignored, so they bubble past this slider entirely instead of being
  // swallowed the way stock Slider's internal Shortcuts used to.
  KeyEventResult _handleMinScoreKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(() => _minScore = (_minScore - 1).clamp(0, 100));
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(() => _minScore = (_minScore + 1).clamp(0, 100));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // Same pattern as _handleMinScoreKey — nudges by 1 year, clamped to
  // [1980, currentYear + 1], matching the slider's own
  // divisions: (currentYear + 1) - 1980 step.
  KeyEventResult _handleYearKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final maxYear = DateTime.now().year.toDouble() + 1;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      setState(
        () => _selectedYear = (_selectedYear - 1).clamp(1980.0, maxYear),
      );
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      setState(
        () => _selectedYear = (_selectedYear + 1).clamp(1980.0, maxYear),
      );
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final isAnyYear = _selectedYear > currentYear;
    final radii = context.appRadii;

    final panelContent = Material(
      color: AppPalette.base.withValues(
        alpha: widget.uiPerformanceMode ? 0.98 : 0.75,
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Filters',
                  style: TextStyle(
                    color: AppPalette.textMain,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppPalette.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 32),

            const Text(
              'Status',
              style: TextStyle(
                color: AppPalette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            AppSegmentedControl<String>(
              autofocus: true,
              items: [
                for (final status in _statusOptions)
                  AppSegmentedControlItem(value: status, label: status),
              ],
              groupValue: _selectedStatus,
              onValueChanged: (value) =>
                  setState(() => _selectedStatus = value),
            ),
            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Minimum Score',
                  style: TextStyle(
                    color: AppPalette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _minScore == 0 ? 'Any' : '$_minScore',
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            AnimatedBuilder(
              animation: _minScoreFocusNode,
              builder: (context, child) => Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radii.small),
                  border: Border.all(
                    color: _minScoreFocusNode.hasFocus
                        ? AppPalette.primary
                        : AppPalette.transparent,
                    width: 2,
                  ),
                ),
                child: child,
              ),
              child: Focus(
                focusNode: _minScoreFocusNode,
                child: SliderTheme(
                  data: const SliderThemeData(
                    activeTrackColor: AppPalette.primary,
                    thumbColor: AppPalette.primary,
                    inactiveTrackColor: AppPalette.border,
                  ),
                  child: Slider(
                    focusNode: _minScoreSliderInternalFocusNode,
                    value: _minScore.toDouble(),
                    max: 100,
                    divisions: 100,
                    onChanged: (val) => setState(() => _minScore = val.toInt()),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Release Year',
                  style: TextStyle(
                    color: AppPalette.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  isAnyYear ? 'Any' : '${_selectedYear.toInt()}',
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            AnimatedBuilder(
              animation: _yearFocusNode,
              builder: (context, child) => Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radii.small),
                  border: Border.all(
                    color: _yearFocusNode.hasFocus
                        ? AppPalette.primary
                        : AppPalette.transparent,
                    width: 2,
                  ),
                ),
                child: child,
              ),
              child: Focus(
                focusNode: _yearFocusNode,
                child: SliderTheme(
                  data: const SliderThemeData(
                    activeTrackColor: AppPalette.primary,
                    thumbColor: AppPalette.primary,
                    inactiveTrackColor: AppPalette.border,
                  ),
                  child: Slider(
                    focusNode: _yearSliderInternalFocusNode,
                    value: _selectedYear,
                    min: 1980,
                    max: currentYear.toDouble() + 1,
                    divisions: (currentYear + 1) - 1980,
                    onChanged: (val) => setState(() => _selectedYear = val),
                  ),
                ),
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: AppPalette.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  widget.onApply(_minScore, _selectedStatus, _selectedYear);
                },
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return FrostedContainer(
      uiPerformanceMode: widget.uiPerformanceMode,
      sigma: context.appMaterials.prominent,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        bottomLeft: Radius.circular(24),
      ),
      child: panelContent,
    );
  }
}
