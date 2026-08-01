import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_palette.dart';
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

  // Segmented status control replaces the old Wrap of ChoiceChips.
  // A single control needs a single FocusNode (rather than one
  //autofocus-able target per chip) — this is also what folds the
  // "three ChoiceChips each had autofocus: true" bug into the fix rather than needing a separate patch.
  late final FocusNode _statusFocusNode;

  static const List<String> _statusOptions = ['ANY', 'RELEASING', 'FINISHED'];

  @override
  void initState() {
    super.initState();
    _minScore = widget.initialMinScore;
    _selectedStatus = widget.initialStatus;
    _selectedYear = widget.initialYear;
    _statusFocusNode = FocusNode(debugLabel: 'StatusSegmentedControl');
    _statusFocusNode.onKeyEvent = _handleStatusKey;
  }

  @override
  void dispose() {
    _statusFocusNode.dispose();
    super.dispose();
  }

  // ── Left/Right always move the segment selection, even at the first/
  // last option — unlike SettingsTextField's cursor-position boundary
  // check, a 3-item enumerated control has no "content" to keep moving
  // through, so there's no case where handing off to spatial traversal on
  // this axis makes sense. Up/Down are always ignored, letting dpad's own
  // focusInDirection move focus to the Minimum Score slider above or
  // Release Year slider below — same "local axis vs. escape axis" split
  // DESIGN.md documents for SettingsTextField, just with fixed rather
  // than position-dependent axes. ──
  KeyEventResult _handleStatusKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final currentIndex = _statusOptions.indexOf(_selectedStatus);

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (currentIndex > 0) {
        setState(() => _selectedStatus = _statusOptions[currentIndex - 1]);
      }
      return KeyEventResult.handled;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (currentIndex < _statusOptions.length - 1) {
        setState(() => _selectedStatus = _statusOptions[currentIndex + 1]);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final isAnyYear = _selectedYear > currentYear;

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
            Focus(
              focusNode: _statusFocusNode,
              autofocus: true,
              child: CupertinoSlidingSegmentedControl<String>(
                backgroundColor: AppPalette.surface,
                thumbColor: AppPalette.primary,
                groupValue: _selectedStatus,
                // ── Static AppPalette.textMain for every segment
                // regardless of selection — CupertinoSlidingSegmentedControl
                // takes plain child widgets per segment, not a
                // per-selection builder the way ChoiceChip's labelStyle
                // callback allowed. Near-white reads fine against both
                // AppPalette.surface (track) and AppPalette.primary
                // (thumb), so this is a legibility-neutral simplification,
                // flagged per DESIGN.md § 5's design-debt convention
                // rather than silently dropped. ──
                children: {
                  for (final status in _statusOptions)
                    status: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        status,
                        style: const TextStyle(
                          color: AppPalette.textMain,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                },
                onValueChanged: (value) {
                  if (value != null) setState(() => _selectedStatus = value);
                },
              ),
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
            SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppPalette.primary,
                thumbColor: AppPalette.primary,
                inactiveTrackColor: AppPalette.border,
              ),
              child: Slider(
                value: _minScore.toDouble(),
                max: 100,
                divisions: 100,
                onChanged: (val) => setState(() => _minScore = val.toInt()),
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
            SliderTheme(
              data: const SliderThemeData(
                activeTrackColor: AppPalette.primary,
                thumbColor: AppPalette.primary,
                inactiveTrackColor: AppPalette.border,
              ),
              child: Slider(
                value: _selectedYear,
                min: 1980,
                max: currentYear.toDouble() + 1,
                divisions: (currentYear + 1) - 1980,
                onChanged: (val) => setState(() => _selectedYear = val),
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
      sigma: 30,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(24),
        bottomLeft: Radius.circular(24),
      ),
      child: panelContent,
    );
  }
}
