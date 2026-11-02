import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/util/language_preference_selection.dart';

/// Where [LanguagePreferences] are kept. Device only: they go nowhere near the
/// server, which has no place for them.
const languagePreferencesKey = 'languagePreferences';

final languagePreferencesProvider =
    StateNotifierProvider<LanguagePreferencesNotifier, LanguagePreferences>((ref) {
  return LanguagePreferencesNotifier(ref);
});

/// The play the person last pressed, when it was a collection's or a
/// playlist's: the scope a film in it remembers its languages under. Set by
/// those play buttons, cleared by any other play.
final playbackOriginProvider = StateProvider<LanguageScope?>((ref) => null);

class LanguagePreferencesNotifier extends StateNotifier<LanguagePreferences> {
  LanguagePreferencesNotifier(this.ref) : super(_load(ref));

  final Ref ref;

  /// Read while items are parsed, so never in the way of one: without a
  /// store to read (a test, say) there simply are no preferences.
  static LanguagePreferences _load(Ref ref) {
    try {
      return LanguagePreferences.fromJson(ref.read(sharedPreferencesProvider).getString(languagePreferencesKey));
    } catch (_) {
      return const LanguagePreferences();
    }
  }

  @override
  set state(LanguagePreferences value) {
    super.state = value;
    ref.read(sharedPreferencesProvider).setString(languagePreferencesKey, value.toJson());
  }

  /// Read again after the stored copy was replaced, by an import.
  void reload() => super.state = _load(ref);

  void setAskToRemember(bool value) => state = state.copyWith(askToRemember: value);

  void remember(RememberedLanguages choice) => state = state.copyWith(
        remembered: {...state.remembered, choice.key: choice},
      );

  void forget(String key) => state = state.copyWith(
        remembered: Map.of(state.remembered)..remove(key),
      );

  void forgetAllOf(String userId) => state = state.copyWith(
        remembered: Map.of(state.remembered)..removeWhere((_, value) => value.userId == userId),
      );

  /// Adds [rule], or replaces the one for the same language.
  void setRule(LanguageRule rule) {
    final rules = [...state.rules];
    final at = rules.indexWhere((existing) => existing.language == rule.language);
    if (at >= 0) {
      rules[at] = rule;
    } else {
      rules.add(rule);
    }
    state = state.copyWith(rules: rules);
  }

  void removeRule(String language) => state = state.copyWith(
        rules: state.rules.where((rule) => rule.language != language).toList(),
      );
}

/// [streams] with the tracks the language preferences ask for as defaults:
/// what was remembered for [scopeId] (the show, for an episode), or else the
/// rule for the original language. Applied as an item is read, so the details
/// page shows the same tracks the player is about to use.
MediaStreamsModel applyLanguagePreferences(Ref ref, MediaStreamsModel streams, {String? scopeId}) {
  final preferences = ref.read(languagePreferencesProvider);
  if (preferences.rules.isEmpty && preferences.remembered.isEmpty) return streams;
  final remembered = preferences.rememberedFor(ref.read(userProvider)?.id, scopeId);
  return streams.withLanguagePreferences(preferences, remembered: remembered);
}

/// [streams] with what was remembered for the collection or playlist
/// [originId], as the player picks them when the item is played from there
/// (see [playbackLanguages]): not over tracks picked by hand, nor over a
/// choice remembered for the show [seriesId].
MediaStreamsModel applyOriginLanguages(Ref ref, MediaStreamsModel streams,
    {required String originId, String? seriesId}) {
  final preferences = ref.read(languagePreferencesProvider);
  final userId = ref.read(userProvider)?.id;
  if (streams.pickedByHand || preferences.rememberedFor(userId, seriesId) != null) return streams;
  final remembered = preferences.rememberedFor(userId, originId);
  if (remembered == null) return streams;
  return streams.withLanguagePreferences(preferences, remembered: remembered);
}
