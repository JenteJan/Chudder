import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/cultures_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/screens/shared/adaptive_dialog.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/util/language_names.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/subtitle_track_selection.dart';
import 'package:chudder/widgets/shared/alert_content.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

/// Everything the app keeps about languages on this device: how to play a
/// film by the language it was made in, and the choices remembered per show,
/// collection and playlist - each of which can be set back from here.
Future<void> showLanguagePreferences(BuildContext context) => showDialogAdaptive(
      context: context,
      builder: (context) => const _LanguagePreferencesView(),
    );

/// A one-line account of what a rule or remembered choice plays.
String _describe(
  BuildContext context,
  List<CultureDto> cultures, {
  required String? audio,
  required bool keepOriginal,
  required SubtitleRuleMode subtitles,
  required String? subtitleLanguage,
}) {
  final l10n = context.localized;
  final audioText = keepOriginal
      ? l10n.languageOriginalAudio
      : audio == null
          ? l10n.languageServerAudio
          : l10n.languageAudioIn(languageName(audio, cultures));
  final subtitleText = switch (subtitles) {
    SubtitleRuleMode.server => l10n.languageServerSubtitles,
    SubtitleRuleMode.off => l10n.languageSubtitlesOff,
    SubtitleRuleMode.language => subtitleLanguage == null
        ? l10n.languageServerSubtitles
        : l10n.languageSubtitlesIn(languageName(subtitleLanguage, cultures)),
  };
  return '$audioText · $subtitleText';
}

Future<String?> _pickLanguage(BuildContext context, List<CultureDto> cultures, String title) async {
  final code = await showTvDialog<String>(
    context: context,
    builder: (context) => LanguagePicker(cultures: cultures, title: title),
  );
  if (code == null) return null;
  final normalized = normalizeLanguage(code);
  return normalized.isEmpty ? null : normalized;
}

class _LanguagePreferencesView extends ConsumerWidget {
  const _LanguagePreferencesView();

  Future<void> _addRule(BuildContext context, WidgetRef ref, List<CultureDto> cultures) async {
    final language = await _pickLanguage(context, cultures, context.localized.languageRuleWhichLanguage);
    if (language == null || !context.mounted) return;
    final existing = ref.read(languagePreferencesProvider).rules.where((rule) => rule.language == language);
    await _editRule(context, ref, existing.firstOrNull ?? LanguageRule(language: language));
  }

  Future<void> _editRule(BuildContext context, WidgetRef ref, LanguageRule rule) async {
    final edited = await showTvDialog<LanguageRule>(
      context: context,
      builder: (context) => _RuleEditor(rule: rule),
    );
    if (edited != null) ref.read(languagePreferencesProvider.notifier).setRule(edited);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preferences = ref.watch(languagePreferencesProvider);
    final notifier = ref.read(languagePreferencesProvider.notifier);
    final cultures = ref.watch(culturesProvider);
    final userId = ref.watch(userProvider.select((user) => user?.id));
    final remembered = preferences.remembered.values.where((choice) => choice.userId == userId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final rules = [...preferences.rules]..sort((a, b) {
        // "Any other language" last, the rest by name.
        if (a.language == LanguageRule.anyLanguage) return 1;
        if (b.language == LanguageRule.anyLanguage) return -1;
        return languageName(a.language, cultures).compareTo(languageName(b.language, cultures));
      });
    final hasAnyRule = rules.any((rule) => rule.language == LanguageRule.anyLanguage);

    Widget header(String title, String description) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary)),
              Text(description, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        );

    Widget empty(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: TvDialogSurface(
        child: ActionContent(
          title: Text(context.localized.languagePreferences, style: theme.textTheme.titleLarge),
          child: ListView(
            shrinkWrap: true,
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                value: preferences.askToRemember,
                onChanged: notifier.setAskToRemember,
                title: Text(context.localized.languageAskToRemember),
                subtitle: Text(context.localized.languageAskToRememberDesc),
              ),
              header(context.localized.languageRulesTitle, context.localized.languageRulesDesc),
              if (rules.isEmpty) empty(context.localized.languageRulesEmpty),
              for (final rule in rules)
                _PreferenceTile(
                  icon: rule.language == LanguageRule.anyLanguage
                      ? IconsaxPlusLinear.global
                      : IconsaxPlusLinear.language_square,
                  title: rule.language == LanguageRule.anyLanguage
                      ? context.localized.languageAnyOther
                      : languageName(rule.language, cultures),
                  subtitle: _describe(
                    context,
                    cultures,
                    audio: rule.audioLanguage,
                    keepOriginal: rule.keepOriginalAudio,
                    subtitles: rule.subtitles,
                    subtitleLanguage: rule.subtitleLanguage,
                  ),
                  onTap: () => _editRule(context, ref, rule),
                  onRemove: () => notifier.removeRule(rule.language),
                  removeLabel: context.localized.languageRuleRemove,
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _addRule(context, ref, cultures),
                    icon: const Icon(IconsaxPlusLinear.add, size: 18),
                    label: Text(context.localized.languageRuleAdd),
                  ),
                  if (!hasAnyRule)
                    TextButton.icon(
                      onPressed: () => _editRule(context, ref, const LanguageRule(language: LanguageRule.anyLanguage)),
                      icon: const Icon(IconsaxPlusLinear.global, size: 18),
                      label: Text(context.localized.languageRuleAddAny),
                    ),
                ],
              ),
              header(context.localized.languageRememberedTitle, context.localized.languageRememberedDesc),
              if (remembered.isEmpty) empty(context.localized.languageRememberedEmpty),
              for (final choice in remembered)
                _PreferenceTile(
                  icon: switch (choice.kind) {
                    LanguageScopeKind.series => IconsaxPlusLinear.video_vertical,
                    LanguageScopeKind.collection => IconsaxPlusLinear.archive_book,
                    LanguageScopeKind.playlist => IconsaxPlusLinear.music_playlist,
                  },
                  title: choice.name,
                  subtitle: _describe(
                    context,
                    cultures,
                    audio: choice.audioLanguage,
                    keepOriginal: false,
                    subtitles: choice.subtitlesOff
                        ? SubtitleRuleMode.off
                        : (choice.subtitleLanguage == null ? SubtitleRuleMode.server : SubtitleRuleMode.language),
                    subtitleLanguage: choice.subtitleLanguage,
                  ),
                  onRemove: () => notifier.forget(choice.key),
                  removeLabel: context.localized.languageRememberedReset,
                ),
              if (remembered.length > 1 && userId != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => notifier.forgetAllOf(userId),
                    icon: const Icon(IconsaxPlusLinear.refresh_left_square, size: 18),
                    label: Text(context.localized.languageRememberedResetAll),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Icon(IconsaxPlusLinear.info_circle, size: 16, color: scheme.onSurfaceVariant),
                  Expanded(
                    child: Text(
                      context.localized.languagePreferencesDeviceOnly,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.localized.done),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    required this.removeLabel,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: scheme.primary),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: IconButton(
            tooltip: removeLabel,
            onPressed: onRemove,
            icon: const Icon(IconsaxPlusLinear.trash),
          ),
        ),
      ),
    );
  }
}

/// How films made in one language play: the audio, kept original or dubbed,
/// and the subtitles.
class _RuleEditor extends ConsumerStatefulWidget {
  const _RuleEditor({required this.rule});
  final LanguageRule rule;

  @override
  ConsumerState<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends ConsumerState<_RuleEditor> {
  late LanguageRule _rule = widget.rule;

  /// The language the person reads and listens in, to start a dub or a
  /// subtitle choice from: the account's preference for [audio] or subtitles
  /// on the server, else the language the app is shown in.
  String _usualLanguage({required bool audio}) {
    final config = ref.read(userProvider)?.userConfiguration;
    final fromAccount = normalizeLanguage(
      (audio ? config?.audioLanguagePreference : config?.subtitleLanguagePreference) ?? '',
    );
    if (fromAccount.isNotEmpty) return fromAccount;
    final locale = ref.read(clientSettingsProvider).selectedLocale ?? Localizations.localeOf(context);
    return normalizeLanguage(locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cultures = ref.watch(culturesProvider);
    final any = _rule.language == LanguageRule.anyLanguage;
    final languageLabel = any ? context.localized.languageAnyOther : languageName(_rule.language, cultures);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
        );

    Widget languageButton(String? code, String placeholder, ValueChanged<String> onPicked) => OutlinedButton.icon(
          onPressed: () async {
            final picked = await _pickLanguage(context, cultures, placeholder);
            if (picked != null) onPicked(picked);
          },
          icon: const Icon(IconsaxPlusLinear.language_square, size: 18),
          label: Text(code == null ? placeholder : languageName(code, cultures)),
        );

    final dubbed = !_rule.keepOriginalAudio;
    final canSave = (!dubbed || _rule.audioLanguage != null) &&
        (_rule.subtitles != SubtitleRuleMode.language || _rule.subtitleLanguage != null);

    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.language_square),
      title: Text(any ? context.localized.languageAnyOther : context.localized.languageRuleFor(languageLabel)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                any ? context.localized.languageRuleAnyDesc : context.localized.languageRuleDesc(languageLabel),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              label(context.localized.audio(1)),
              _Choices<bool>(
                selected: _rule.keepOriginalAudio,
                options: {
                  true: context.localized.languageKeepOriginal,
                  false: context.localized.languagePreferDub,
                },
                onSelected: (value) => setState(() => _rule = _rule.copyWith(
                      keepOriginalAudio: value,
                      audioLanguage: value || _rule.audioLanguage != null ? null : () => _usualLanguage(audio: true),
                    )),
              ),
              if (dubbed) ...[
                const SizedBox(height: 8),
                languageButton(
                  _rule.audioLanguage,
                  context.localized.languagePickDub,
                  (code) => setState(() => _rule = _rule.copyWith(audioLanguage: () => code)),
                ),
                const SizedBox(height: 4),
                Text(
                  context.localized.languageDubFallback,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              label(context.localized.subtitles),
              _Choices<SubtitleRuleMode>(
                selected: _rule.subtitles,
                options: {
                  SubtitleRuleMode.server: context.localized.languageAsServer,
                  SubtitleRuleMode.off: context.localized.off,
                  SubtitleRuleMode.language: context.localized.languageALanguage,
                },
                onSelected: (value) => setState(() => _rule = _rule.copyWith(
                      subtitles: value,
                      subtitleLanguage: value != SubtitleRuleMode.language || _rule.subtitleLanguage != null
                          ? null
                          : () => _usualLanguage(audio: false),
                    )),
              ),
              if (_rule.subtitles == SubtitleRuleMode.language) ...[
                const SizedBox(height: 8),
                languageButton(
                  _rule.subtitleLanguage,
                  context.localized.languagePickSubtitles,
                  (code) => setState(() => _rule = _rule.copyWith(subtitleLanguage: () => code)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
        FilledButton(
          onPressed: canSave ? () => Navigator.of(context).pop(_rule) : null,
          child: Text(context.localized.save),
        ),
      ],
    );
  }
}

/// One of a few choices, as chips that wrap onto a second line on a narrow
/// screen instead of squeezing their words.
class _Choices<T> extends StatelessWidget {
  const _Choices({required this.selected, required this.options, required this.onSelected});

  final T selected;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options.entries)
          ChoiceChip(
            label: Text(option.value),
            selected: option.key == selected,
            onSelected: (_) => onSelected(option.key),
          ),
      ],
    );
  }
}
