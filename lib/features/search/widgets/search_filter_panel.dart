import 'dart:ui';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

class SearchFilterPanel extends StatefulWidget {
  final int initialMinScore;
  final String initialStatus;
  final double initialYear;
  final void Function(int minScore, String status, double year) onApply;

  const SearchFilterPanel({
    super.key,
    required this.initialMinScore,
    required this.initialStatus,
    required this.initialYear,
    required this.onApply,
  });

  @override
  State<SearchFilterPanel> createState() => _SearchFilterPanelState();
}

class _SearchFilterPanelState extends State<SearchFilterPanel> {
  late int _minScore;
  late String _selectedStatus;
  late double _selectedYear;

  @override
  void initState() {
    super.initState();
    _minScore = widget.initialMinScore;
    _selectedStatus = widget.initialStatus;
    _selectedYear = widget.initialYear;
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final isAnyYear = _selectedYear > currentYear;

    return ClipRRect(
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), bottomLeft: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Material(
          color: AppPalette.base.withValues(alpha: 0.75),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filters', style: TextStyle(color: AppPalette.textMain, fontSize: 24, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: AppPalette.textMuted), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 32),
                
                // ── Status Filter ──
                const Text('Status', style: TextStyle(color: AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['ANY', 'RELEASING', 'FINISHED'].map((status) {
                    final isSelected = _selectedStatus == status;
                    return ChoiceChip(
                      label: Text(status),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedStatus = status);
                      },
                      backgroundColor: AppPalette.surface,
                      selectedColor: AppPalette.primary.withValues(alpha: 0.2),
                      labelStyle: TextStyle(color: isSelected ? AppPalette.primary : AppPalette.textMain, fontSize: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: isSelected ? AppPalette.primary : AppPalette.border),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),

                // ── Minimum Score Filter ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Minimum Score', style: TextStyle(color: AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(_minScore == 0 ? 'Any' : '$_minScore', style: const TextStyle(color: AppPalette.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: const SliderThemeData(activeTrackColor: AppPalette.primary, thumbColor: AppPalette.primary, inactiveTrackColor: AppPalette.border),
                  child: Slider(
                    value: _minScore.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    onChanged: (val) => setState(() => _minScore = val.toInt()),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Year Filter ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Release Year', style: TextStyle(color: AppPalette.textMuted, fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(isAnyYear ? 'Any' : '${_selectedYear.toInt()}', style: const TextStyle(color: AppPalette.primary, fontWeight: FontWeight.bold)),
                  ],
                ),
                SliderTheme(
                  data: const SliderThemeData(activeTrackColor: AppPalette.primary, thumbColor: AppPalette.primary, inactiveTrackColor: AppPalette.border),
                  child: Slider(
                    value: _selectedYear,
                    min: 1980,
                    max: currentYear.toDouble() + 1,
                    divisions: (currentYear + 1) - 1980,
                    onChanged: (val) => setState(() => _selectedYear = val),
                  ),
                ),

                const Spacer(),
                
                // ── Apply Button ──
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.primary, 
                      foregroundColor: AppPalette.white, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onApply(_minScore, _selectedStatus, _selectedYear);
                    },
                    child: const Text('Apply Filters', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}