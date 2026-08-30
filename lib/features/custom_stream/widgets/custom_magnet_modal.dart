import 'package:flutter/material.dart';

import '../../../core/extensions/build_context_extensions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../shared/widgets/selection_modal.dart';
import '../../../shared/widgets/settings_text_field.dart';

/// Centered-card modal collecting a raw magnet link to stream directly,
/// bypassing AniList/Nyaa.si entirely — see [SelectionModal]'s doc
/// comment for the shared chrome this and [TorrentSearchModal]/
/// [BatchEpisodePickerOverlay] all build on. Mounted as a real pushed
/// route via [show]; the resolved [Future] carries the validated magnet
/// URI, or `null` if the modal was dismissed without a submission
/// (backdrop tap, close button) — the same `showDialog<T>`-style
/// contract [TorrentSearchModal.show] uses.
///
/// A stream started this way has no `Anime`/episode context, so
/// `TheaterScreen` never arms AniList progress tracking for it — the
/// subtitle text below says so explicitly, since it's a real behavioral
/// difference from every other way of starting a stream in this app.
class CustomMagnetModal extends StatefulWidget {
  final bool uiPerformanceMode;

  const CustomMagnetModal({super.key, this.uiPerformanceMode = false});

  static Future<String?> show({
    required BuildContext context,
    bool uiPerformanceMode = false,
  }) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Stream a magnet link',
      // Transparent — the darkening lives entirely in SelectionModal's
      // own full-screen backdrop, same reasoning as TorrentSearchModal.
      barrierColor: AppPalette.transparent,
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, _) =>
          CustomMagnetModal(uiPerformanceMode: uiPerformanceMode),
    );
  }

  @override
  State<CustomMagnetModal> createState() => _CustomMagnetModalState();
}

class _CustomMagnetModalState extends State<CustomMagnetModal> {
  // Light, fast-fail validation only — not a full magnet-URI parse. The
  // real validation is whatever StreamingController/RemoteStreamingController
  // eventually do with it; a bad-but-prefix-matching link still surfaces
  // as a normal TheaterLoadingOverlay error via their existing
  // _handleError/_setError paths.
  static const String _magnetPrefix = 'magnet:?xt=urn:btih:';

  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  void _handleSubmit() {
    final raw = _controller.text.trim();
    if (!raw.toLowerCase().startsWith(_magnetPrefix)) {
      setState(
        () => _errorText =
            'Enter a valid magnet link — it should start with "$_magnetPrefix".',
      );
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final radii = context.appRadii;

    return SelectionModal(
      icon: Icons.link_rounded,
      title: 'Stream a Magnet Link',
      subtitle:
          'Paste a magnet link to stream it directly. AniList progress '
          "tracking is off for this stream, since there's no episode to "
          'log it against.',
      regionMemoryKey: 'customStream.magnetModal',
      uiPerformanceMode: widget.uiPerformanceMode,
      onClose: () => Navigator.of(context).pop(),
      onBackdropTap: () => Navigator.of(context).pop(),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsTextField(
              controller: _controller,
              hint: 'magnet:?xt=urn:btih:...',
              label: 'Magnet Link',
              autofocus: true,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(
                  color: AppPalette.statusCancelled,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: AppPalette.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radii.small),
                  ),
                ),
                child: const Text(
                  'Stream',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
