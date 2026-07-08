import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../services/streaming_controller.dart';

class BatchEpisodePickerOverlay extends StatelessWidget {
  final List<BatchFileOption> files;
  final int? requestedEpisode;
  final void Function(int fileIndex) onSelect;
  final VoidCallback? onBack;
  final bool dpadModeActive;

  const BatchEpisodePickerOverlay({
    super.key,
    required this.files,
    required this.onSelect,
    this.requestedEpisode,
    this.onBack,
    this.dpadModeActive = false,
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
    return FocusScope(
      autofocus: true,
      child: Container(
        color: AppPalette.black.withValues(alpha: 0.85),
        child: Center(
          child: Container(
            width: 440,
            constraints: const BoxConstraints(maxHeight: 480),
            decoration: BoxDecoration(
              color: AppPalette.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppPalette.white.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.video_library_outlined,
                        color: AppPalette.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'This is a batch torrent',
                          style: TextStyle(
                            color: AppPalette.textMain,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (onBack != null)
                        IconButton(
                          tooltip: 'Go back',
                          icon: const Icon(
                            Icons.close_rounded,
                            color: AppPalette.textMuted,
                            size: 20,
                          ),
                          onPressed: onBack,
                          splashRadius: 18,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    requestedEpisode != null
                        ? "We couldn't confidently match Episode $requestedEpisode inside it — pick the right file below."
                        : 'Multiple episodes were found inside this torrent — pick one to start streaming.',
                    style: const TextStyle(
                      color: AppPalette.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Divider(color: AppPalette.border, height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final f = files[i];
                      final isSuggested =
                          requestedEpisode != null &&
                          f.guessedEpisode == requestedEpisode;

                      return ListTile(
                        autofocus: i == 0,
                        focusColor: dpadModeActive
                            ? AppPalette.white.withValues(alpha: 0.1)
                            : AppPalette.transparent,
                        hoverColor: AppPalette.white.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: CircleAvatar(
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
                        title: Text(
                          f.guessedEpisode != null
                              ? 'Episode ${f.guessedEpisode}'
                              : f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppPalette.textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        trailing: Column(
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
                        onTap: () => onSelect(f.index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
