import 'dart:convert';

/// What a remembered choice belongs to.
enum LanguageScopeKind { series, collection, playlist }

/// A show, collection or playlist whose language choice can be remembered.
class LanguageScope {
  const LanguageScope({required this.id, required this.name, required this.kind});

  final String id;
  final String name;
  final LanguageScopeKind kind;
}

/// The audio and subtitle language chosen for one show, collection or
/// playlist, kept so the next episode or film starts with them.
///
/// Languages are kept as normalized codes (see `normalizeLanguage`); the
/// track is found again by language on each item, not by its number, which
/// differs from file to file.
class RememberedLanguages {
  const RememberedLanguages({
    required this.userId,
    required this.scopeId,
    required this.name,
    required this.kind,
    this.audioLanguage,
    this.subtitleLanguage,
    this.subtitlesOff = false,
    required this.savedAt,
  });

  final String userId;
  final String scopeId;
  final String name;
  final LanguageScopeKind kind;

  /// Null leaves the audio as the server picks it.
  final String? audioLanguage;

  /// Null with [subtitlesOff] false leaves the subtitles as the server picks.
  final String? subtitleLanguage;
  final bool subtitlesOff;
  final DateTime savedAt;

  String get key => keyFor(userId, scopeId);

  static String keyFor(String userId, String scopeId) => '$userId:$scopeId';

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'scopeId': scopeId,
        'name': name,
        'kind': kind.name,
        'audioLanguage': audioLanguage,
        'subtitleLanguage': subtitleLanguage,
        'subtitlesOff': subtitlesOff,
        'savedAt': savedAt.toIso8601String(),
      };

  static RememberedLanguages? fromMap(Map<String, dynamic> map) {
    final userId = map['userId'] as String?;
    final scopeId = map['scopeId'] as String?;
    if (userId == null || scopeId == null) return null;
    return RememberedLanguages(
      userId: userId,
      scopeId: scopeId,
      name: map['name'] as String? ?? '',
      kind: LanguageScopeKind.values.asNameMap()[map['kind']] ?? LanguageScopeKind.series,
      audioLanguage: map['audioLanguage'] as String?,
      subtitleLanguage: map['subtitleLanguage'] as String?,
      subtitlesOff: map['subtitlesOff'] as bool? ?? false,
      savedAt: DateTime.tryParse(map['savedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// What to do with the subtitles under a [LanguageRule].
enum SubtitleRuleMode {
  /// Whatever the server picks.
  server,
  off,

  /// The rule's [LanguageRule.subtitleLanguage].
  language,
}

/// How to play anything whose original language is [language]: in that
/// language, or dubbed into another; and with which subtitles.
///
/// The original language is read from the first audio track in the file,
/// which is where releases put it. [anyLanguage] stands for every original
/// language without a rule of its own.
class LanguageRule {
  const LanguageRule({
    required this.language,
    this.keepOriginalAudio = true,
    this.audioLanguage,
    this.subtitles = SubtitleRuleMode.server,
    this.subtitleLanguage,
  });

  static const anyLanguage = '*';

  final String language;
  final bool keepOriginalAudio;

  /// The dub to prefer when not [keepOriginalAudio]; the original plays when
  /// a file has none.
  final String? audioLanguage;
  final SubtitleRuleMode subtitles;
  final String? subtitleLanguage;

  LanguageRule copyWith({
    String? language,
    bool? keepOriginalAudio,
    String? Function()? audioLanguage,
    SubtitleRuleMode? subtitles,
    String? Function()? subtitleLanguage,
  }) =>
      LanguageRule(
        language: language ?? this.language,
        keepOriginalAudio: keepOriginalAudio ?? this.keepOriginalAudio,
        audioLanguage: audioLanguage != null ? audioLanguage() : this.audioLanguage,
        subtitles: subtitles ?? this.subtitles,
        subtitleLanguage: subtitleLanguage != null ? subtitleLanguage() : this.subtitleLanguage,
      );

  Map<String, dynamic> toMap() => {
        'language': language,
        'keepOriginalAudio': keepOriginalAudio,
        'audioLanguage': audioLanguage,
        'subtitles': subtitles.name,
        'subtitleLanguage': subtitleLanguage,
      };

  static LanguageRule? fromMap(Map<String, dynamic> map) {
    final language = map['language'] as String?;
    if (language == null || language.isEmpty) return null;
    return LanguageRule(
      language: language,
      keepOriginalAudio: map['keepOriginalAudio'] as bool? ?? true,
      audioLanguage: map['audioLanguage'] as String?,
      subtitles: SubtitleRuleMode.values.asNameMap()[map['subtitles']] ?? SubtitleRuleMode.server,
      subtitleLanguage: map['subtitleLanguage'] as String?,
    );
  }
}

/// Language choices kept on this device: remembered per show, collection and
/// playlist, and rules per original language.
class LanguagePreferences {
  const LanguagePreferences({
    this.askToRemember = true,
    this.remembered = const {},
    this.rules = const [],
  });

  /// Whether changing the audio or subtitles in the player offers to
  /// remember the choice.
  final bool askToRemember;

  /// By [RememberedLanguages.key].
  final Map<String, RememberedLanguages> remembered;
  final List<LanguageRule> rules;

  RememberedLanguages? rememberedFor(String? userId, String? scopeId) {
    if (userId == null || scopeId == null) return null;
    return remembered[RememberedLanguages.keyFor(userId, scopeId)];
  }

  /// The rule for [originalLanguage], or the one for any language.
  LanguageRule? ruleFor(String originalLanguage) {
    for (final rule in rules) {
      if (rule.language == originalLanguage) return rule;
    }
    for (final rule in rules) {
      if (rule.language == LanguageRule.anyLanguage) return rule;
    }
    return null;
  }

  LanguagePreferences copyWith({
    bool? askToRemember,
    Map<String, RememberedLanguages>? remembered,
    List<LanguageRule>? rules,
  }) =>
      LanguagePreferences(
        askToRemember: askToRemember ?? this.askToRemember,
        remembered: remembered ?? this.remembered,
        rules: rules ?? this.rules,
      );

  Map<String, dynamic> toMap() => {
        'askToRemember': askToRemember,
        'remembered': remembered.values.map((e) => e.toMap()).toList(),
        'rules': rules.map((e) => e.toMap()).toList(),
      };

  String toJson() => jsonEncode(toMap());

  static LanguagePreferences fromMap(Map<String, dynamic> map) {
    final remembered = <String, RememberedLanguages>{};
    for (final entry in (map['remembered'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final value = RememberedLanguages.fromMap(Map<String, dynamic>.from(entry));
      if (value != null) remembered[value.key] = value;
    }
    return LanguagePreferences(
      askToRemember: map['askToRemember'] as bool? ?? true,
      remembered: remembered,
      rules: [
        for (final entry in (map['rules'] as List? ?? const []))
          if (entry is Map) LanguageRule.fromMap(Map<String, dynamic>.from(entry)),
      ].nonNulls.toList(),
    );
  }

  static LanguagePreferences fromJson(String? source) {
    if (source == null || source.isEmpty) return const LanguagePreferences();
    try {
      return fromMap(Map<String, dynamic>.from(jsonDecode(source) as Map));
    } catch (_) {
      return const LanguagePreferences();
    }
  }
}
