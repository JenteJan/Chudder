import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/remembered_queue_provider.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/watched_languages_provider.dart';

/// The parts of the app's settings that travel to another device, each the
/// stored value of one key (see `SharedKeys`). Accounts and logins never do,
/// and neither does what only says where this device has been.
enum SettingsSection {
  app('clientSettings'),
  home('homeSettings'),
  player('videoPlayerSettings'),
  subtitles('subtitleSettings'),
  languages(languagePreferencesKey),
  syncPlay('syncPlaySettings'),
  books('bookViewSettings'),
  photos('photoViewSettings'),
  collectionQueues(rememberedQueuesKey),
  watchedLanguages(watchedLanguagesKey);

  const SettingsSection(this.key);
  final String key;

  /// Fields that describe this device rather than a taste, kept as they are
  /// here when settings come in from elsewhere: a download folder on another
  /// disk, a window position on another screen, a player that other platform
  /// may not have.
  Set<String> get deviceOnly => switch (this) {
        // The OMDb key is a secret: it stays where it was typed.
        SettingsSection.app => const {
            'syncPath',
            'position',
            'size',
            'lastViewedUpdate',
            'forceLeanBackMode',
            'omdbApiKey',
          },
        // The volume as well: on a phone it is the system's media volume,
        // which turned a desktop silent the moment a profile carried it over.
        SettingsSection.player => const {'playerOptions', 'audioDevice', 'screenBrightness', 'internalVolume'},
        _ => const {},
      };
}

/// Settings exported from one Chudder, to be read into another.
class SettingsBundle {
  const SettingsBundle({required this.exportedAt, required this.device, required this.sections});

  static const format = 'chudder-settings';
  static const version = 1;

  final DateTime exportedAt;

  /// Where it was exported from, to recognise it by: "1.2.0 (Windows)".
  final String device;

  /// The stored value per section, as JSON.
  final Map<SettingsSection, Object?> sections;

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': exportedAt.toIso8601String(),
        'device': device,
        'settings': {for (final entry in sections.entries) entry.key.key: entry.value},
      });

  /// Null for anything that is not an export of these settings.
  static SettingsBundle? decode(String source) {
    try {
      final map = jsonDecode(source);
      if (map is! Map || map['format'] != format) return null;
      final settings = map['settings'];
      if (settings is! Map) return null;
      final sections = <SettingsSection, Object?>{};
      for (final section in SettingsSection.values) {
        if (settings.containsKey(section.key)) sections[section] = settings[section.key];
      }
      return SettingsBundle(
        exportedAt: DateTime.tryParse('${map['exportedAt']}') ?? DateTime.now(),
        device: '${map['device'] ?? ''}',
        sections: sections,
      );
    } catch (_) {
      return null;
    }
  }

  /// What this device has stored now.
  static SettingsBundle collect(SharedPreferences preferences, {required String device}) {
    final sections = <SettingsSection, Object?>{};
    for (final section in SettingsSection.values) {
      final stored = preferences.getString(section.key);
      if (stored == null || stored.isEmpty) continue;
      Object? value;
      try {
        value = jsonDecode(stored);
      } catch (_) {
        value = stored;
      }
      // Leaving out what only means something here.
      if (value is Map && section.deviceOnly.isNotEmpty) {
        value = Map.of(value)..removeWhere((key, _) => section.deviceOnly.contains(key));
      }
      sections[section] = value;
    }
    return SettingsBundle(exportedAt: DateTime.now(), device: device, sections: sections);
  }

  /// Stores [only] of these sections over this device's, keeping each
  /// section's [SettingsSection.deviceOnly] fields as they were here. The
  /// providers still hold the old values: read them in again afterwards.
  Future<void> writeTo(SharedPreferences preferences, Set<SettingsSection> only) async {
    for (final section in only) {
      if (!sections.containsKey(section)) continue;
      var value = sections[section];
      if (value is Map && section.deviceOnly.isNotEmpty) {
        final current = _decodedMap(preferences.getString(section.key));
        value = {
          ...Map<String, dynamic>.from(value)..removeWhere((key, _) => section.deviceOnly.contains(key)),
          for (final key in section.deviceOnly)
            if (current.containsKey(key)) key: current[key],
        };
      }
      await preferences.setString(section.key, value is String ? value : jsonEncode(value));
    }
  }

  static Map<String, dynamic> _decodedMap(String? stored) {
    if (stored == null || stored.isEmpty) return const {};
    try {
      final value = jsonDecode(stored);
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }
}
