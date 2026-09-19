import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

/// Minimal, player-engine-agnostic surface a control-bar widget needs:
/// current playing/position/duration/buffer/volume, plus the methods
/// that change them. `TheaterControls` (desktop) stays wired directly to
/// media_kit's `Player`, unaffected by this — the interface exists so
/// `MobileTheaterControls` doesn't depend on either player package
/// directly. `PlayerPlaybackHandle` below is the media_kit-backed
/// implementation this was originally built to allow for.
///
/// Streams mirror media_kit's own `Player.stream.*` shape for exactly
/// that reason.
abstract class PlaybackHandle {
  bool get isPlaying;
  Stream<bool> get playingStream;

  Duration get position;
  Stream<Duration> get positionStream;

  Duration get duration;
  Stream<Duration> get durationStream;

  Duration get buffer;
  Stream<Duration> get bufferStream;

  /// 0-100, matching the scale `TheaterControls`' volume slider already
  /// uses — callers never need to know the underlying engine's native
  /// scale.
  double get volume;
  Stream<double> get volumeStream;

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// Available audio tracks for this session, or an empty list on an
  /// engine that doesn't expose audio-track switching. Concrete with a
  /// safe default — like `BaseStreamingController`'s subtitle methods —
  /// since only `VideoPlayerPlaybackHandle` implements it today. A plain
  /// one-shot `Future`, not a stream: video_player's tracks API has no
  /// change-notification of its own, so a caller fetches this once after
  /// the player is ready and caches the result, the same way
  /// `ExoTheaterScreen` already does for subtitles.
  Future<List<VideoAudioTrack>> getAudioTracks() async => const [];

  /// Selects an audio track by the id [getAudioTracks] reported for it.
  /// No-op on an engine that doesn't support audio-track switching.
  Future<void> selectAudioTrack(String trackId) async {}

  /// Releases this handle's own listeners/stream controllers. Never
  /// disposes the underlying player/controller — the caller that
  /// constructed it still owns that lifecycle.
  void dispose();
}

/// [PlaybackHandle] backed by `video_player`'s [VideoPlayerController].
///
/// `VideoPlayerController` is itself a `ValueNotifier<VideoPlayerValue>`
/// with no per-field streams of its own, so this listens once and fans
/// out into the separate broadcast streams [PlaybackHandle] exposes,
/// each only emitting when that specific field actually changed —
/// unlike a single combined listener, which would notify on every
/// unrelated field change too.
class VideoPlayerPlaybackHandle implements PlaybackHandle {
  final VideoPlayerController _controller;

  final _playingController = StreamController<bool>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration>.broadcast();
  final _bufferController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<double>.broadcast();

  late bool _lastPlaying;
  late Duration _lastPosition;
  late Duration _lastDuration;
  late Duration _lastBuffer;
  late double _lastVolume;

  VideoPlayerPlaybackHandle(this._controller) {
    final value = _controller.value;
    _lastPlaying = value.isPlaying;
    _lastPosition = value.position;
    _lastDuration = value.duration;
    _lastBuffer = _bufferedEnd(value);
    _lastVolume = value.volume * 100;
    _controller.addListener(_onControllerChanged);
  }

  static Duration _bufferedEnd(VideoPlayerValue value) =>
      value.buffered.isEmpty ? Duration.zero : value.buffered.last.end;

  void _onControllerChanged() {
    final value = _controller.value;

    final playing = value.isPlaying;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      _playingController.add(playing);
    }

    final position = value.position;
    if (position != _lastPosition) {
      _lastPosition = position;
      _positionController.add(position);
    }

    final duration = value.duration;
    if (duration != _lastDuration) {
      _lastDuration = duration;
      _durationController.add(duration);
    }

    final buffer = _bufferedEnd(value);
    if (buffer != _lastBuffer) {
      _lastBuffer = buffer;
      _bufferController.add(buffer);
    }

    final volume = value.volume * 100;
    if (volume != _lastVolume) {
      _lastVolume = volume;
      _volumeController.add(volume);
    }
  }

  @override
  bool get isPlaying => _lastPlaying;
  @override
  Stream<bool> get playingStream => _playingController.stream;

  @override
  Duration get position => _lastPosition;
  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Duration get duration => _lastDuration;
  @override
  Stream<Duration> get durationStream => _durationController.stream;

  @override
  Duration get buffer => _lastBuffer;
  @override
  Stream<Duration> get bufferStream => _bufferController.stream;

  @override
  double get volume => _lastVolume;
  @override
  Stream<double> get volumeStream => _volumeController.stream;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> playOrPause() =>
      _lastPlaying ? _controller.pause() : _controller.play();

  @override
  Future<void> seek(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) =>
      _controller.setVolume((volume / 100).clamp(0.0, 1.0));

  @override
  Future<List<VideoAudioTrack>> getAudioTracks() => _controller.getAudioTracks();

  @override
  Future<void> selectAudioTrack(String trackId) =>
      _controller.selectAudioTrack(trackId);

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    unawaited(_playingController.close());
    unawaited(_positionController.close());
    unawaited(_durationController.close());
    unawaited(_bufferController.close());
    unawaited(_volumeController.close());
  }
}

/// [PlaybackHandle] backed by media_kit's [Player] — used by
/// [MobileTheaterControls] when `TheaterScreen` renders its
/// touch-oriented control bar (Android/iOS, Android TV included) instead
/// of the desktop-only `TheaterControls`, which stays wired to [Player]
/// directly and never touches this class.
///
/// A genuinely thin pass-through, more so than [VideoPlayerPlaybackHandle]
/// above: [Player] already exposes a broadcast stream per field
/// (`stream.playing`, `.position`, `.duration`, `.buffer`, `.volume`), so
/// every stream getter below just forwards the matching [Player] stream
/// directly, with no owned [StreamController] needed to fan a single
/// listener out into several — unlike [VideoPlayerController], which is
/// a single [ValueNotifier] with no per-field streams of its own. Volume
/// needs no rescaling either: both [Player] and [PlaybackHandle] use a
/// 0-100 scale, unlike [VideoPlayerController]'s 0-1.
///
/// `extends` rather than `implements` — unlike [VideoPlayerPlaybackHandle]
/// — specifically so [getAudioTracks]/[selectAudioTrack] inherit
/// [PlaybackHandle]'s own no-op default instead of this class repeating
/// it: `TheaterScreen`'s settings popup (`DesktopTheaterSettingsMenu`)
/// already talks to [Player]'s own `Tracks`/`setAudioTrack` directly and
/// has no reason to route audio-track selection through this handle.
class PlayerPlaybackHandle extends PlaybackHandle {
  final Player _player;

  PlayerPlaybackHandle(this._player);

  @override
  bool get isPlaying => _player.state.playing;
  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Duration get position => _player.state.position;
  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Duration get duration => _player.state.duration;
  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Duration get buffer => _player.state.buffer;
  @override
  Stream<Duration> get bufferStream => _player.stream.buffer;

  @override
  double get volume => _player.state.volume;
  @override
  Stream<double> get volumeStream => _player.stream.volume;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  void dispose() {
    // No owned subscriptions or controllers to tear down — every stream
    // above forwards Player's own broadcast stream directly rather than
    // deriving a new one. Player's lifecycle belongs to whoever
    // constructed it (TheaterScreen), matching this method's contract
    // per PlaybackHandle's own doc comment above.
  }
}