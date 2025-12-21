import 'dart:async';

// Stub for audio_service on Tizen
// Tizen handles media controls differently

enum AudioProcessingState {
  idle,
  loading,
  buffering,
  ready,
  completed,
  error,
}

enum MediaAction {
  stop,
  pause,
  play,
  rewind,
  skipToPrevious,
  skipToNext,
  fastForward,
  setRating,
  seek,
  playPause,
  playFromMediaId,
  playFromSearch,
  skipToQueueItem,
  playFromUri,
  prepare,
  prepareFromMediaId,
  prepareFromSearch,
  prepareFromUri,
  setRepeatMode,
  setShuffleMode,
  setSpeed,
}

class MediaControl {
  final String label;
  final String action;
  final int? icon;

  const MediaControl({
    required this.label,
    required this.action,
    this.icon,
  });

  static const MediaControl play = MediaControl(label: 'Play', action: 'play');
  static const MediaControl pause = MediaControl(label: 'Pause', action: 'pause');
  static const MediaControl stop = MediaControl(label: 'Stop', action: 'stop');
  static const MediaControl rewind = MediaControl(label: 'Rewind', action: 'rewind');
  static const MediaControl fastForward = MediaControl(label: 'Fast Forward', action: 'fastForward');
  static const MediaControl skipToNext = MediaControl(label: 'Skip to Next', action: 'skipToNext');
  static const MediaControl skipToPrevious = MediaControl(label: 'Skip to Previous', action: 'skipToPrevious');
}

class Rating {
  final bool hasHeart;

  const Rating._(this.hasHeart);

  static Rating newHeartRating(bool hasHeart) => Rating._(hasHeart);
}

class MediaItem {
  final String id;
  final String title;
  final String? album;
  final String? artist;
  final String? genre;
  final Duration? duration;
  final Uri? artUri;
  final Map<String, dynamic>? extras;
  final Rating? rating;
  final String? displayTitle;
  final String? displaySubtitle;
  final String? displayDescription;
  final bool? playable;

  const MediaItem({
    required this.id,
    required this.title,
    this.album,
    this.artist,
    this.genre,
    this.duration,
    this.artUri,
    this.extras,
    this.rating,
    this.displayTitle,
    this.displaySubtitle,
    this.displayDescription,
    this.playable,
  });
}

class PlaybackState {
  final List<MediaControl> controls;
  final Set<MediaAction> systemActions;
  final AudioProcessingState processingState;
  final bool playing;
  final Duration updatePosition;
  final Duration bufferedPosition;
  final double speed;
  final int? queueIndex;
  final bool? repeatMode;
  final bool? shuffleMode;
  final String? errorMessage;
  final int? errorCode;

  const PlaybackState({
    this.controls = const [],
    this.systemActions = const {},
    this.processingState = AudioProcessingState.idle,
    this.playing = false,
    this.updatePosition = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.speed = 1.0,
    this.queueIndex,
    this.repeatMode,
    this.shuffleMode,
    this.errorMessage,
    this.errorCode,
  });

  PlaybackState copyWith({
    List<MediaControl>? controls,
    Set<MediaAction>? systemActions,
    AudioProcessingState? processingState,
    bool? playing,
    Duration? updatePosition,
    Duration? bufferedPosition,
    double? speed,
    int? queueIndex,
    bool? repeatMode,
    bool? shuffleMode,
    String? errorMessage,
    int? errorCode,
  }) {
    return PlaybackState(
      controls: controls ?? this.controls,
      systemActions: systemActions ?? this.systemActions,
      processingState: processingState ?? this.processingState,
      playing: playing ?? this.playing,
      updatePosition: updatePosition ?? this.updatePosition,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      speed: speed ?? this.speed,
      queueIndex: queueIndex ?? this.queueIndex,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      errorMessage: errorMessage ?? this.errorMessage,
      errorCode: errorCode ?? this.errorCode,
    );
  }
}

class AudioServiceConfig {
  final String androidNotificationChannelId;
  final String androidNotificationChannelName;
  final String? androidNotificationChannelDescription;
  final bool androidNotificationOngoing;
  final bool androidStopForegroundOnPause;
  final Duration rewindInterval;
  final Duration fastForwardInterval;
  final bool androidShowNotificationBadge;

  const AudioServiceConfig({
    this.androidNotificationChannelId = 'audio_service_channel',
    this.androidNotificationChannelName = 'Audio Service',
    this.androidNotificationChannelDescription,
    this.androidNotificationOngoing = false,
    this.androidStopForegroundOnPause = true,
    this.rewindInterval = const Duration(seconds: 10),
    this.fastForwardInterval = const Duration(seconds: 30),
    this.androidShowNotificationBadge = false,
  });
}

class AudioService {
  static Future<T> init<T extends BaseAudioHandler>({
    required T Function() builder,
    AudioServiceConfig? config,
  }) async {
    return builder();
  }
}

abstract class BaseAudioHandler {
  final BehaviorSubject<PlaybackState> playbackState = BehaviorSubject.seeded(const PlaybackState());
  final BehaviorSubject<MediaItem?> mediaItem = BehaviorSubject.seeded(null);
  final BehaviorSubject<List<MediaItem>> queue = BehaviorSubject.seeded([]);

  Future<void> play() async {}
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> seek(Duration position) async {}
  Future<void> setSpeed(double speed) async {}
  Future<void> fastForward() async {}
  Future<void> rewind() async {}
  Future<void> skipToNext() async {}
  Future<void> skipToPrevious() async {}
}

// Simple BehaviorSubject implementation for the stub
class BehaviorSubject<T> {
  T _value;
  final StreamController<T> _controller = StreamController<T>.broadcast();

  BehaviorSubject.seeded(T seed) : _value = seed;

  T get value => _value;

  Stream<T> get stream => _controller.stream;

  void add(T value) {
    _value = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}


