import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'pip_args.dart';

class PipPlayerWindow extends StatefulWidget {
  final PipArgs args;
  const PipPlayerWindow({super.key, required this.args});

  @override
  State<PipPlayerWindow> createState() => _PipPlayerWindowState();
}

class _PipPlayerWindowState extends State<PipPlayerWindow> {
  late final Player _player;
  late final VideoController _videoController;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _player = Player(configuration: const PlayerConfiguration(libass: true));
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );
    _initWindow();
    _registerWindowMethodHandler();
    _configurePlayer();

    _player.open(Media(widget.args.streamUrl!));
    _player.stream.duration.firstWhere((d) => d > Duration.zero).then((
      _,
    ) async {
      _player.seek(Duration(milliseconds: widget.args.positionMs));
      await _notifyMainWindowReady();
    });
  }

  void _configurePlayer() {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      platform.setProperty('hwdec', 'auto-safe');
      platform.setProperty('cache', 'yes');
      platform.setProperty('demuxer-max-bytes', '150000000');
      platform.setProperty('demuxer-readahead-secs', '120');
    }
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(const Size(400, 225));
    await windowManager.setMinimumSize(const Size(280, 158));
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _registerWindowMethodHandler() async {
    final own = await WindowController.fromCurrentEngine();
    own.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'force_close':
          await _player.dispose();
          await windowManager.close();
        case 'focus_pip':
          await windowManager.show();
          await windowManager.focus();
      }
      return null;
    });
  }

  Future<void> _returnToMain() async {
    if (widget.args.mainWindowId != null) {
      WindowController.fromWindowId(widget.args.mainWindowId!).invokeMethod(
        'pip_returned',
        {'positionMs': _player.state.position.inMilliseconds},
      );
    }
    await _player.dispose();
    await windowManager.close();
  }

  Future<void> _notifyMainWindowReady() async {
    if (widget.args.mainWindowId == null) return;
    try {
      await WindowController.fromWindowId(
        widget.args.mainWindowId!,
      ).invokeMethod('pip_ready');
    } catch (_) {
      // Non-fatal — worst case the main window just stays un-minimized.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _videoController, controls: NoVideoControls),
            // drag handle — frameless window has no titlebar to grab
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 28,
              child: DragToMoveArea(child: SizedBox.expand()),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white,
                    ),
                    onPressed: _returnToMain,
                  ),
                  IconButton(
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      _isPlaying ? _player.pause() : _player.play();
                      setState(() => _isPlaying = !_isPlaying);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
