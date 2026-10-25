import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/selection_modal.dart';
import '../services/streaming_controller.dart';

/// Inline `TheaterScreen` state branch (not a route) for picking a file when
/// a multi-file torrent can't resolve the requested episode; [onBack] exits
/// Theater. Built on [SelectionModal].
class BatchEpisodePickerOverlay extends StatelessWidget {
  final List<BatchFileOption> files;
  final int? requestedEpisode;
  final void Function(int fileIndex) onSelect;
  final VoidCallback? onBack;

  const BatchEpisodePickerOverlay({
    super.key,
    required this.files,
    required this.onSelect,
    this.requestedEpisode,
    this.onBack,
  });

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(1)} ${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    return SelectionModal(
      icon: Icons.video_library_outlined,
      title: 'This is a batch torrent',
      subtitle: requestedEpisode != null
          ? "We couldn't confidently match Episode $requestedEpisode inside it — pick the right file below."
          : 'Multiple episodes were found inside this torrent — pick one to start streaming.',
      regionMemoryKey: 'theater.batchPicker',
      // See DESIGN.md § 5.3.
      uiPerformanceMode: false,
      useGlassEffect: false,
      onClose: onBack,
      body: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: files.length,
        itemBuilder: (context, i) {
          final f = files[i];
          final isSuggested =
              requestedEpisode != null && f.guessedEpisode == requestedEpisode;
          final hasDistinctTitle = f.guessedEpisode != null;

          return DpadFocusable(
            autofocus: i == 0,
            onSelect: () => onSelect(f.index),
            builder: (context, state, child) => Container(
              decoration: BoxDecoration(
                color: state.focused
                    ? AppPalette.white.withValues(alpha: 0.1)
                    : AppPalette.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: isSuggested
                        ? AppPalette.primary.withValues(alpha: 0.2)
                        : AppPalette.white.withValues(alpha: 0.08),
                    child: Text(
                      f.guessedEpisode?.toString() ?? '?',
                      style: TextStyle(
                        color: isSuggested
                            ? AppPalette.primary
                            : AppPalette.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Long filenames wrap rather than truncate.
                        Text(
                          hasDistinctTitle
                              ? 'Episode ${f.guessedEpisode}'
                              : f.name,
                          style: const TextStyle(
                            color: AppPalette.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Skipped when the title above already is f.name.
                        if (hasDistinctTitle) ...[
                          const SizedBox(height: 2),
                          Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppPalette.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isSuggested)
                        const Text(
                          'Suggested',
                          style: TextStyle(
                            color: AppPalette.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        _formatSize(f.size),
                        style: const TextStyle(
                          color: AppPalette.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            child: const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
