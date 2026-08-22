import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/settings/client_settings_page.dart';
import 'package:fladder/screens/settings/player_settings_page.dart';
import 'package:fladder/screens/settings/profile_settings_page.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/widgets/settings_label_divider.dart';
import 'package:fladder/screens/settings/widgets/settings_list_group.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/theme_extensions.dart';

/// A settings row that matched the query, kept together with the page and
/// section it lives on so the result can be labelled and jumped to.
class SettingsSearchHit {
  final String page;
  final String? section;
  final PageRouteInfo route;
  final Widget widget;
  final int score;

  const SettingsSearchHit({
    required this.page,
    required this.section,
    required this.route,
    required this.widget,
    required this.score,
  });

  String get breadcrumb => section == null ? page : "$page  ›  $section";
}

/// Search results ready to drop into a [SettingsScaffold]'s `items`.
///
/// The rows are the real setting widgets rather than links to them, so a
/// setting can be changed straight from the results without opening its page.
/// Every group is headed by a breadcrumb that opens the owning page.
List<Widget> buildSettingsSearchResults(
  BuildContext context,
  WidgetRef ref,
  String query, {
  required Function setState,
  required TextEditingController nextUpDaysEditor,
  required TextEditingController libraryPageSizeController,
  required void Function(PageRouteInfo route) onNavigate,
}) {
  final hits = searchSettings(
    context,
    ref,
    query,
    setState: setState,
    nextUpDaysEditor: nextUpDaysEditor,
    libraryPageSizeController: libraryPageSizeController,
  );

  if (hits.isEmpty) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Column(
          children: [
            Icon(
              IconsaxPlusLinear.search_normal_1,
              size: 42,
              color: context.colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              context.localized.noResults,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ];
  }

  // Group in score order so the strongest match decides where its group lands.
  final groups = <String, List<SettingsSearchHit>>{};
  for (final hit in hits) {
    groups.putIfAbsent(hit.breadcrumb, () => []).add(hit);
  }

  return [
    for (final group in groups.entries) ...[
      _BreadcrumbHeader(
        label: group.key,
        onTap: () => onNavigate(group.value.first.route),
      ),
      ...group.value.indexed.map(
        (entry) => _asGroupChild(entry.$2.widget, isLast: entry.$1 == group.value.length - 1),
      ),
      const SizedBox(height: 12),
    ],
  ];
}

/// Builds every settings page's rows and returns those matching [query],
/// best match first.
///
/// The pages are built but never mounted here, so this walks plain widget
/// objects to read their labels - a page whose rows can't be built (missing
/// user data, for instance) is skipped rather than breaking the search.
List<SettingsSearchHit> searchSettings(
  BuildContext context,
  WidgetRef ref,
  String query, {
  required Function setState,
  required TextEditingController nextUpDaysEditor,
  required TextEditingController libraryPageSizeController,
  int limit = 50,
}) {
  final tokens = _tokenize(query);
  if (tokens.isEmpty) return const [];

  final sources = <(String, PageRouteInfo, List<Widget> Function())>[
    (
      context.localized.settingsClientTitle,
      const ClientSettingsRoute(),
      () => buildClientSettingsItems(
            context,
            ref,
            setState: setState,
            nextUpDaysEditor: nextUpDaysEditor,
            libraryPageSizeController: libraryPageSizeController,
          ),
    ),
    (
      context.localized.settingsPlayerTitle,
      const PlayerSettingsRoute(),
      () => buildPlayerSettingsItems(context, ref),
    ),
    (
      context.localized.settingsProfileTitle,
      const ProfileSettingsRoute(),
      () => buildProfileSettingsItems(context, ref),
    ),
  ];

  final hits = <SettingsSearchHit>[];

  for (final (page, route, builder) in sources) {
    final List<Widget> items;
    try {
      items = builder();
    } catch (_) {
      continue;
    }

    String? section;
    for (final item in items) {
      final header = _sectionTitleOf(item);
      if (header != null) {
        section = header;
        continue;
      }

      final texts = <String>[];
      try {
        _collectText(context, item, texts);
      } catch (_) {
        continue;
      }
      if (texts.isEmpty) continue;

      final title = texts.first;
      final details = [...texts.skip(1), page, if (section != null) section].join(" ");
      final score = _matchScore(tokens, title, details);
      if (score == null) continue;

      hits.add(SettingsSearchHit(
        page: page,
        section: section,
        route: route,
        widget: item,
        score: score,
      ));
    }
  }

  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits.length > limit ? hits.sublist(0, limit) : hits;
}

/// Re-wraps a matched row so the rounded group styling still reads correctly
/// once the row sits in a results group instead of its own page.
Widget _asGroupChild(Widget widget, {required bool isLast}) {
  if (widget is SettingsListChild) {
    return SettingsListChild(isLast: isLast, child: widget.child);
  }
  return SettingsListChild(isLast: isLast, child: widget);
}

class _BreadcrumbHeader extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BreadcrumbHeader({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SettingsListGroupTitle(
      label: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              Icon(
                IconsaxPlusLinear.arrow_right_3,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Matching ---

List<String> _tokenize(String query) =>
    query.toLowerCase().split(RegExp(r'\s+')).where((token) => token.isNotEmpty).toList();

/// Score for [query] against a row, or null when any of its words matches
/// neither the title nor the surrounding text. Title matches count triple so
/// "video" ranks the row actually called "Video" above rows that merely
/// mention it.
int? settingsMatchScore(String query, String title, String details) => _matchScore(_tokenize(query), title, details);

int? _matchScore(List<String> tokens, String title, String details) {
  if (tokens.isEmpty) return null;
  final lowerTitle = title.toLowerCase();
  final lowerDetails = details.toLowerCase();

  var total = 0;
  for (final token in tokens) {
    final inTitle = _tokenScore(token, lowerTitle);
    final inDetails = _tokenScore(token, lowerDetails);
    if (inTitle == null && inDetails == null) return null;
    total += (inTitle ?? 0) * 3 + (inDetails ?? 0);
  }
  return total;
}

/// Scores one token against one string: a straight substring hit beats a
/// fuzzy one, and a hit at the start of a word beats one mid-word.
int? _tokenScore(String token, String text) {
  if (text.isEmpty) return null;

  final index = text.indexOf(token);
  if (index >= 0) {
    var score = 1000 - index.clamp(0, 900);
    if (_startsWord(text, index)) score += 500;
    return score;
  }
  return _subsequenceScore(token, text);
}

/// Fuzzy fallback: every character of the token has to appear in order.
/// Characters that land next to each other, or at the start of a word, score
/// higher, so "vidscal" prefers "Video scaling" over an incidental match.
int? _subsequenceScore(String token, String text) {
  var cursor = 0;
  var score = 0;
  var streak = 0;

  for (var i = 0; i < token.length; i++) {
    final found = text.indexOf(token[i], cursor);
    if (found < 0) return null;
    streak = (i > 0 && found == cursor) ? streak + 1 : 0;
    score += 10 + streak * 5;
    if (_startsWord(text, found)) score += 15;
    cursor = found + 1;
  }
  return score;
}

bool _startsWord(String text, int index) {
  if (index == 0) return true;
  final previous = text[index - 1];
  return !RegExp(r'[a-z0-9]').hasMatch(previous);
}

// --- Widget introspection ---

/// The section heading a settings item declares, if it is one.
String? _sectionTitleOf(Widget widget) {
  if (widget is SettingsLabelDivider) return widget.label;
  if (widget is SettingsListGroupTitle) {
    final label = widget.label;
    if (label is SettingsLabelDivider) return label.label;
  }
  return null;
}

/// The readable text of a settings row, title first.
List<String> settingsRowText(BuildContext context, Widget widget) {
  final out = <String>[];
  _collectText(context, widget, out);
  return out;
}

/// Collects the readable text of a settings row, title first.
///
/// Only the wrappers the settings pages actually use are unpacked; anything
/// else contributes nothing rather than guessing.
void _collectText(BuildContext context, Widget? widget, List<String> out, {int depth = 0}) {
  if (widget == null || depth > 8 || out.length > 12) return;

  void recurse(Widget? child) => _collectText(context, child, out, depth: depth + 1);

  switch (widget) {
    case Text text:
      final value = text.data ?? text.textSpan?.toPlainText();
      if (value != null && value.trim().isNotEmpty) out.add(value.trim());
    case SettingsLabelDivider divider:
      out.add(divider.label);
    case SettingsListTile tile:
      recurse(tile.label);
      recurse(tile.subLabel);
    case SettingsListTileCheckbox tile:
      recurse(tile.label);
      recurse(tile.subLabel);
    case SettingsListTileEnum tile:
      recurse(tile.label);
      recurse(tile.subLabel);
      if (tile.current != null) out.add(tile.current!);
    case SettingsListChild child:
      recurse(child.child);
    case SettingsListGroupTitle title:
      recurse(title.label);
    case ExpansionTile tile:
      recurse(tile.title);
      tile.children.forEach(recurse);
    case AnimatedFadeSize animated:
      recurse(animated.child);
    case Builder builder:
      // Some rows are built lazily; the builders only read localization and
      // theme off the context, so running one here is safe.
      try {
        recurse(builder.builder(context));
      } catch (_) {
        // Skip rows that need a mounted element.
      }
    case Card card:
      recurse(card.child);
    case Container container:
      recurse(container.child);
    case Material material:
      recurse(material.child);
    case InkWell inkWell:
      recurse(inkWell.child);
    case ProxyWidget proxy:
      recurse(proxy.child);
    case SingleChildRenderObjectWidget single:
      recurse(single.child);
    case MultiChildRenderObjectWidget multi:
      multi.children.forEach(recurse);
    default:
      return;
  }
}
