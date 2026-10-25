import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

/// Engine-agnostic playback surface for `MobileTheaterControls`; streams mirror
/// media_kit's `Player.stream.*`.
abstract class PlaybackHandle {
  bool get isPlaying;
  Stream<bool> get playingStream;

  Duration get position;
  Stream<Duration> get positionStream;

  Duration get duration;
  Stream<Duration> get durationStream;

  Duration get buffer;
  Stream<Duration> get bufferStream;

  /// 0-100; implementations convert from the engine's native scale.
  double get volume;
  Stream<double> get volumeStream;

  Future<void> play();
  Future<void> pause();
  Future<void> playOrPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);

  /// Audio tracks for this session; empty on engines without track switching.
  /// A one-shot Future because video_player's tracks API has no change events.
  Future<List<VideoAudioTrack>> getAudioTracks() async => const [];

  /// Selects a track by its [getAudioTracks] id; no-op if unsupported.
  Future<void> selectAudioTrack(String trackId) async {}

  /// Releases this handle's listeners and streams, not the underlying player.
  void dispose();
}

/// [PlaybackHandle] over `video_player`'s [VideoPlayerController], which has no
/// per-field streams: one listener fans out into streams that emit only when
/// their own field changes.
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
  Future<List<VideoAudioTrack>> getAudioTracks() =>
      _controller.getAudioTracks();

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

/// [PlaybackHandle] over media_kit's [Player], used by [MobileTheaterControls].
/// A pass-through ([Player] already exposes per-field streams and 0-100 volume)
/// that extends, so the audio-track methods inherit the no-op default.
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
    // Nothing owned: streams forward Player's; TheaterScreen owns Player.
  }
}
