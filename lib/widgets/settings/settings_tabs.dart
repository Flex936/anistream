import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import 'settings_components.dart';

class GeneralTab extends StatelessWidget {
  final bool filterEcchi;
  final String downloadFolder;
  final ValueChanged<bool> onFilterEcchiChanged;
  final VoidCallback onPickDownloadFolder;

  const GeneralTab({
    super.key,
    required this.filterEcchi,
    required this.downloadFolder,
    required this.onFilterEcchiChanged,
    required this.onPickDownloadFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TabHeading(title: 'General Settings'),

        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FILTER ECCHI CONTENT',
                  style: TextStyle(
                    color: AppPalette.textMain,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Hide borderline NSFW shows.',
                  style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
                ),
              ],
            ),
            ToggleSwitch(value: filterEcchi, onChanged: onFilterEcchiChanged),
          ],
        ),

        const SizedBox(height: 20),
        const Divider(color: AppPalette.border, height: 1),
        const SizedBox(height: 20),

        const SectionLabel(label: 'Download Directory'),
        const SizedBox(height: 4),
        const Text(
          'Change your temporary downloads folder.',
          style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FolderInput(path: downloadFolder, onTap: onPickDownloadFolder),
      ],
    );
  }
}

class PlaybackTab extends StatelessWidget {
  const PlaybackTab({super.key});
  @override
  Widget build(BuildContext context) => const TodoPane(tabName: 'Playback');
}

class UpscaleTab extends StatelessWidget {
  const UpscaleTab({super.key});
  @override
  Widget build(BuildContext context) => const TodoPane(tabName: 'Upscale');
}

class TodoPane extends StatelessWidget {
  final String tabName;
  const TodoPane({super.key, required this.tabName});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 340,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.construction_rounded,
              color: AppPalette.textMuted,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              '$tabName settings coming soon.',
              style: const TextStyle(color: AppPalette.textMuted, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
