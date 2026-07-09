import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/shared_provider.dart';

/// Persisted, user-tunable SyncPlay settings.
///
/// Kept as a plain (non-freezed) model to match the lightweight settings
/// stores in this project (e.g. `PhotoViewSettingsModel`) — no code generation
/// required.
class SyncPlaySettingsModel {
  /// Manual clock trim, in milliseconds, added on top of the measured NTP
  /// offset when converting between local and server time. Lets a viewer whose
  /// playback consistently sits ahead of or behind the group nudge themselves
  /// back into alignment. Positive = play further ahead of the group.
  final int timeOffsetMs;

  SyncPlaySettingsModel({
    this.timeOffsetMs = 0,
  });

  /// Bounds for [timeOffsetMs] (mirrors jellyfin-web's ±2s `extraTimeOffset`).
  static const int minTimeOffsetMs = -2000;
  static const int maxTimeOffsetMs = 2000;

  SyncPlaySettingsModel copyWith({
    int? timeOffsetMs,
  }) {
    return SyncPlaySettingsModel(
      timeOffsetMs: timeOffsetMs ?? this.timeOffsetMs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timeOffsetMs': timeOffsetMs,
    };
  }

  factory SyncPlaySettingsModel.fromMap(Map<String, dynamic> map) {
    return SyncPlaySettingsModel(
      timeOffsetMs: (map['timeOffsetMs'] as int?) ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory SyncPlaySettingsModel.fromJson(String source) => SyncPlaySettingsModel.fromMap(json.decode(source));
}

final syncPlaySettingsProvider = StateNotifierProvider<SyncPlaySettingsNotifier, SyncPlaySettingsModel>((ref) {
  return SyncPlaySettingsNotifier(ref);
});

class SyncPlaySettingsNotifier extends StateNotifier<SyncPlaySettingsModel> {
  SyncPlaySettingsNotifier(this.ref) : super(SyncPlaySettingsModel());

  final Ref ref;

  @override
  set state(SyncPlaySettingsModel value) {
    super.state = value;
    ref.read(sharedUtilityProvider).syncPlaySettings = value;
  }

  /// Set the manual clock trim, clamped to the supported range.
  void setTimeOffsetMs(int value) => state = state.copyWith(
        timeOffsetMs: value.clamp(
          SyncPlaySettingsModel.minTimeOffsetMs,
          SyncPlaySettingsModel.maxTimeOffsetMs,
        ),
      );

  SyncPlaySettingsModel update(SyncPlaySettingsModel Function(SyncPlaySettingsModel state) cb) => state = cb(state);
}
