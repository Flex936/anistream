import 'dart:async';

import 'package:video_player/video_player.dart';

/// Minimal, player-engine-agnostic surface a control-bar widget needs:
/// current playing/position/duration/buffer/volume, plus the methods
/// that change them. `TheaterControls` (desktop) stays wired directly to
/// media_kit's `Player`, unaffected by this — the interface exists so
/// `MobileTheaterControls` doesn't depend on either player package
/// directly, and a future media_kit-backed implementation could slot in
/// as a thin pass-through rather than a redesign.
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