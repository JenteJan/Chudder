import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/cultures_provider.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/settings_sync_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/language_names.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/subtitle_track_selection.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

final _log = Logger('Playback');

/// The languages playing right now: the audio's, and the subtitles' or off.
typedef PlayingLanguages = ({String? audio, String? subtitle, bool subtitlesOff});

PlayingLanguages? _playingLanguages(PlaybackModel? model) => languagesOf(model?.mediaStreams);

/// The languages [streams] play with their default tracks.
PlayingLanguages? languagesOf(MediaStreamsModel? streams) {
  if (streams == null) return null;
  final audio = streams.currentAudioStream;
  final sub = streams.currentSubStream;
  final subtitlesOff = sub == null || sub.index == -1;
  String? code(String? language) {
    final value = normalizeLanguage(language ?? '');
    return value.isEmpty ? null : value;
  }

  return (
    audio: audio == null || audio.index == -1 ? null : code(audio.language),
    subtitle: subtitlesOff ? null : code(sub.language),
    subtitlesOff: subtitlesOff,
  );
}

/// What a language choice made while [model] plays would be remembered for:
/// the show, for an episode; else the collection or playlist that was played,
/// while this is one of its items. Nothing for a film on its own.
LanguageScope? playbackLanguageScope(PlaybackModel model, LanguageScope? origin) {
  final item = model.item;
  if (item is EpisodeModel && item.parentId != null) {
    return LanguageScope(id: item.parentId!, name: item.seriesName ?? item.name, kind: LanguageScopeKind.series);
  }
  // A film played on its own has no queue to be found in; its collection
  // was looked up for it.
  if (origin != null && (model.queue.length <= 1 || model.queue.any((queued) => queued.id == item.id))) return origin;
  return null;
}

/// Shows that were offered and said "not now" to, while the app is open:
/// asked once is enough until next time.
final Set<String> _notNow = {};

/// Forgets every "not now", as a restart would.
@visibleForTesting
void forgetNotNow() => _notNow.clear();

/// Runs [picker] - a track picker in the player - and, when it changed the
/// audio or subtitles of a show, collection or playlist, offers to remember
/// the new languages for the rest of it. Not offered when switched off in the
/// settings, or when the choice is the one already remembered.
Future<T?> offerToRememberLanguages<T>(BuildContext context, Future<T?> Function() picker) async {
  final container = ProviderScope.containerOf(context, listen: false);
  // The picker may have been opened from a sheet that is gone by the time it
  // closes; the root navigator is still there.
  final navigator = Navigator.of(context, rootNavigator: true);
  final before = _playingLanguages(container.read(playBackModel));
  final result = await picker();

  final model = container.read(playBackModel);
  final after = _playingLanguages(model);
  if (model == null || after == null || after == before) {
    _log.info('languages: no change to offer ($before -> $after)');
    return result;
  }
  final scope = playbackLanguageScope(model, container.read(playbackOriginProvider));
  if (scope == null || !navigator.mounted) {
    _log.info('languages: ${model.item.name} belongs to no show, collection or playlist to remember for');
    return result;
  }
  await askToRememberLanguages(navigator.context, container, scope, after);
  return result;
}

/// Offers to remember [languages] for [scope], unless that is switched off,
/// already remembered, or was turned down earlier while the app is open.
Future<void> askToRememberLanguages(
  BuildContext context,
  ProviderContainer container,
  LanguageScope scope,
  PlayingLanguages languages,
) async {
  final preferences = container.read(languagePreferencesProvider);
  final userId = container.read(userProvider)?.id;
  final String? skip = switch (scope) {
    _ when !preferences.askToRemember => 'switched off in the settings',
    _ when userId == null => 'nobody signed in',
    _ when _notNow.contains(scope.id) => 'turned down for ${scope.name} earlier',
    _ => null,
  };
  if (skip != null) {
    _log.info('languages: not offering for ${scope.name}: $skip');
    return;
  }
  if (userId == null) return;
  final existing = preferences.rememberedFor(userId, scope.id);
  if (existing != null &&
      existing.audioLanguage == languages.audio &&
      existing.subtitlesOff == languages.subtitlesOff &&
      existing.subtitleLanguage == languages.subtitle) {
    _log.info('languages: ${scope.name} already remembers these');
    return;
  }
  if (!context.mounted) return;
  _log.info('languages: offering to remember $languages for ${scope.name}');
  await showTvDialog(
    context: context,
    builder: (context) => RememberLanguagesDialog(
      scope: scope,
      languages: languages,
      onAnswer: (remember, dontAskAgain, languages) {
        final notifier = container.read(languagePreferencesProvider.notifier);
        if (dontAskAgain) notifier.setAskToRemember(false);
        if (!remember) {
          _notNow.add(scope.id);
          return;
        }
        notifier.remember(RememberedLanguages(
          userId: userId,
          scopeId: scope.id,
          name: scope.name,
          kind: scope.kind,
          audioLanguage: languages.audio,
          subtitleLanguage: languages.subtitle,
          subtitlesOff: languages.subtitlesOff,
          savedAt: DateTime.now(),
        ));
      },
    ),
  );
}

/// The question itself, as [askToRememberLanguages] puts it.
class RememberLanguagesDialog extends ConsumerStatefulWidget {
  const RememberLanguagesDialog({required this.scope, required this.languages, required this.onAnswer, super.key});

  final LanguageScope scope;
  final PlayingLanguages languages;

  /// With the languages as they stand when answered: they can be changed
  /// in the dialog first, the tracks playing not always being the ones meant.
  final void Function(bool remember, bool dontAskAgain, PlayingLanguages languages) onAnswer;

  @override
  ConsumerState<RememberLanguagesDialog> createState() => _RememberLanguagesDialogState();
}

class _RememberLanguagesDialogState extends ConsumerState<RememberLanguagesDialog> {
  bool _dontAskAgain = false;
  late PlayingLanguages _languages = widget.languages;

  void _answer(bool remember) {
    widget.onAnswer(remember, _dontAskAgain, _languages);
    Navigator.of(context).pop();
  }

  Future<void> _editAudio(List<CultureDto> cultures) async {
    final code = await showTvDialog<String>(
      context: context,
      builder: (context) => LanguagePicker(cultures: cultures, title: context.localized.audio(1)),
    );
    final language = normalizeLanguage(code ?? '');
    if (language.isEmpty || !mounted) return;
    setState(
        () => _languages = (audio: language, subtitle: _languages.subtitle, subtitlesOff: _languages.subtitlesOff));
  }

  Future<void> _editSubtitles(List<CultureDto> cultures) async {
    final code = await showTvDialog<String>(
      context: context,
      builder: (context) => LanguagePicker(
        cultures: cultures,
        title: context.localized.subtitles,
        offLabel: context.localized.off,
      ),
    );
    if (code == null || !mounted) return;
    final language = normalizeLanguage(code);
    setState(() => _languages = (
          audio: _languages.audio,
          subtitle: language.isEmpty ? null : language,
          subtitlesOff: language.isEmpty,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cultures = ref.watch(culturesProvider);
    final languages = _languages;
    final shared = ref.watch(settingsSyncProvider.select((state) => state.setup.shareMemories));
    final question = switch (widget.scope.kind) {
      LanguageScopeKind.series => context.localized.rememberLanguagesSeries(widget.scope.name),
      LanguageScopeKind.collection => context.localized.rememberLanguagesCollection(widget.scope.name),
      LanguageScopeKind.playlist => context.localized.rememberLanguagesPlaylist(widget.scope.name),
    };

    // Each language a button of its own: pressed, it picks another.
    Widget row(IconData icon, String label, String value, VoidCallback onTap) => FocusButton(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          darkOverlay: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              spacing: 12,
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                SizedBox(width: 92, child: Text(label, style: theme.textTheme.bodyMedium)),
                Expanded(
                  child: Text(value, style: theme.textTheme.titleSmall),
                ),
                Icon(IconsaxPlusLinear.edit_2, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        );

    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.language_square),
      title: Text(context.localized.rememberLanguagesTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            Text(question, style: theme.textTheme.bodyLarge),
            Text(
              context.localized.rememberLanguagesEditHint,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                spacing: 2,
                children: [
                  row(
                    IconsaxPlusLinear.volume_high,
                    context.localized.audio(1),
                    // A track that names no language is remembered as no
                    // choice: the server keeps picking the audio.
                    languages.audio == null
                        ? context.localized.languageAsServer
                        : languageName(languages.audio!, cultures),
                    () => _editAudio(cultures),
                  ),
                  row(
                    IconsaxPlusLinear.subtitle,
                    context.localized.subtitles,
                    languages.subtitlesOff
                        ? context.localized.off
                        : languageName(languages.subtitle ?? '', cultures).ifEmpty(context.localized.languageAsServer),
                    () => _editSubtitles(cultures),
                  ),
                ],
              ),
            ),
            CheckboxListTile(
              value: _dontAskAgain,
              onChanged: (value) => setState(() => _dontAskAgain = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(context.localized.rememberLanguagesDontAsk),
            ),
            // Quiet on purpose: worth knowing, not worth reading first.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Icon(IconsaxPlusLinear.info_circle, size: 16, color: scheme.onSurfaceVariant),
                Expanded(
                  child: Text(
                    shared
                        ? context.localized.rememberLanguagesEveryDevice
                        : context.localized.rememberLanguagesDeviceOnly,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _answer(false), child: Text(context.localized.rememberLanguagesNotNow)),
        FilledButton(
          autofocus: true,
          onPressed: () => _answer(true),
          child: Text(context.localized.rememberLanguagesRemember),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
