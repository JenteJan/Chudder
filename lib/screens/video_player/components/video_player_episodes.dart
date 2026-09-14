import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/details_screens/components/item_toggle_buttons.dart';
import 'package:chudder/screens/shared/media/episode_posters.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/humanize_duration.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

/// The episodes of the show [current] belongs to, as far as [queue] holds
/// them, in queue order.
///
/// Nothing is fetched: the queue is the whole show when playback started from
/// an episode, a season or the series - see [PlaybackModelHelper.collectQueue]
/// - and the playlist when it started from one. Only the current show's
/// episodes out of it, because a playlist that mixes shows would otherwise
/// put every show's season one on the same picker with nothing to tell them
/// apart. Empty when a film is playing.
List<EpisodeModel> browsableEpisodes(ItemBaseModel? current, List<ItemBaseModel> queue) {
  if (current is! EpisodeModel) return const [];
  return queue.whereType<EpisodeModel>().where((episode) => episode.parentId == current.parentId).toList();
}

/// Whether there is a show to browse. One episode is nowhere to go.
bool canBrowseEpisodes(PlaybackModel? model) => browsableEpisodes(model?.item, model?.queue ?? const []).length > 1;

/// The show's episodes in a panel over the video, the way a streaming service
/// does it: the picture keeps playing, the panel slides in from the side (up
/// from the bottom when the phone is upright), and a tap on an episode swaps
/// what is playing. Nothing to open when [canBrowseEpisodes] says no.
Future<void> showPlayerEpisodes(BuildContext context, WidgetRef ref) {
  final model = ref.read(playBackModel);
  final current = model?.item;
  final episodes = browsableEpisodes(current, model?.queue ?? const []);
  if (current is! EpisodeModel || episodes.length < 2) return Future.value();

  final navigator = Navigator.of(context, rootNavigator: true);
  // The player paints itself in the dark theme through a Theme of its own.
  // showDialog carries that into what it opens; a general dialog does not,
  // so it is carried by hand or the panel comes up in the app's light theme.
  final themes = InheritedTheme.capture(from: context, to: navigator.context);

  return showGeneralDialog(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: context.localized.close,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fromSide = _fromSide(context);
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: fromSide ? const Offset(0.12, 0) : const Offset(0, 0.12), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return themes.wrap(
        TvDialogFrame(
          child: Align(
            alignment: _fromSide(context) ? AlignmentDirectional.centerEnd : Alignment.bottomCenter,
            child: _EpisodePanel(episodes: episodes, currentEpisode: current),
          ),
        ),
      );
    },
  );
}

/// Whether the panel comes in from the side or up from the bottom. A window
/// wider than it is tall has room beside the picture; an upright phone has
/// room under it.
bool _fromSide(BuildContext context) => MediaQuery.orientationOf(context) == Orientation.landscape;

/// How tall one episode is in the list. Fixed, so the list can be opened at
/// the episode that is playing without laying out everything above it.
const double _tileExtent = 100;

class _EpisodePanel extends ConsumerStatefulWidget {
  final List<EpisodeModel> episodes;
  final EpisodeModel currentEpisode;

  const _EpisodePanel({required this.episodes, required this.currentEpisode});

  @override
  ConsumerState<_EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends ConsumerState<_EpisodePanel> {
  late final Map<int, List<EpisodeModel>> _bySeason = widget.episodes.episodesBySeason;
  late final int _currentIndex = widget.episodes.indexWhere((episode) => episode.id == widget.currentEpisode.id);

  /// The season on show, null being the whole run. Opens on the one that is
  /// playing: that is where the next episode is.
  late int? _season = widget.currentEpisode.season;

  late final ScrollController _scroll = ScrollController(initialScrollOffset: _offsetOfCurrent(_visible));

  /// One node per episode for the life of the panel, so the selection can be
  /// put on a given episode after the list has been re-parked on it.
  final Map<String, FocusNode> _tileNodes = {};

  FocusNode _nodeFor(EpisodeModel episode) => _tileNodes.putIfAbsent(episode.id, () => FocusNode(debugLabel: episode.id));

  List<EpisodeModel> get _visible => _season == null ? widget.episodes : (_bySeason[_season] ?? const []);

  /// The pills' order: the whole run first, then the seasons.
  List<int?> get _seasonOrder => [null, ..._bySeason.keys];

  /// Where to open the list so the playing episode sits one row down from the
  /// top - what came before for context, what comes next in view.
  double _offsetOfCurrent(List<EpisodeModel> episodes) {
    final index = episodes.indexWhere((episode) => episode.id == widget.currentEpisode.id);
    return math.max(0, (index - 1) * _tileExtent);
  }

  /// Shows [season] and re-parks the list. With [moveFocus] the selection
  /// goes with it - onto the playing episode when it is in this season, and
  /// the season's first otherwise - because the tile that held it is gone.
  void _setSeason(int? season, {bool moveFocus = false}) {
    if (season == _season) return;
    setState(() => _season = season);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final episodes = _visible;
      _scroll.jumpTo(_offsetOfCurrent(episodes).clamp(0, _scroll.position.maxScrollExtent));
      if (!moveFocus || episodes.isEmpty) return;
      // Once more round: the jump builds the tiles at the new offset, and a
      // node only takes the selection once its tile is built.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = episodes.firstWhere((e) => e.id == widget.currentEpisode.id, orElse: () => episodes.first);
        final node = _nodeFor(target);
        if (node.context != null) node.requestFocus();
      });
    });
  }

  /// Left and right in the list step through the pills, so a remote does not
  /// have to climb out of the episodes to get to the next season.
  KeyEventResult _stepSeason(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final int delta;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      delta = -1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      delta = 1;
    } else {
      return KeyEventResult.ignored;
    }
    final order = _seasonOrder;
    final next = (order.indexOf(_season) + delta).clamp(0, order.length - 1);
    _setSeason(order[next], moveFocus: true);
    // Taken even at the ends: letting it through would send the selection
    // off sideways to wherever traversal finds, which is nowhere useful.
    return KeyEventResult.handled;
  }

  void _select(EpisodeModel episode) {
    // Read ahead of the pop: the panel and its ref are on the way out after it.
    final helper = ref.read(playbackModelHelper);
    Navigator.of(context).pop();
    if (episode.id == widget.currentEpisode.id) return;
    helper.loadNewVideo(episode);
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _tileNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final fromSide = _fromSide(context);
    final episodes = _visible;
    final blurUpcoming = ref.watch(clientSettingsProvider.select((value) => value.blurUpcomingEpisodes)) &&
        !widget.episodes.allPlayed;
    final isDPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final seasonNames = seasonNamesFor(context, widget.episodes, const [], bySeason: _bySeason);

    final hairline = BorderSide(color: colors.onSurface.withValues(alpha: 0.08));
    return Material(
      color: colors.surface.withValues(alpha: 0.94),
      shape: fromSide
          ? Border(left: hairline)
          : RoundedRectangleBorder(
              side: hairline,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: fromSide ? math.min(460, size.width * 0.9) : size.width,
        height: fromSide ? size.height : size.height * 0.75,
        child: SafeArea(
          left: false,
          top: fromSide,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: widget.currentEpisode.seriesName ?? widget.currentEpisode.name,
                subtitle: context.localized.seasonEpisodeCount(_bySeason.length, widget.episodes.length),
              ),
              if (_bySeason.length > 1)
                _SeasonChips(
                  names: seasonNames,
                  selected: _season,
                  onSelected: _setSeason,
                ),
              Divider(height: 1, color: hairline.color),
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _stepSeason,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemExtent: _tileExtent,
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrent = episode.id == widget.currentEpisode.id;
                      final position = _season == null ? index : widget.episodes.indexOf(episode);
                      return _EpisodeTile(
                        episode: episode,
                        focusNode: _nodeFor(episode),
                        isCurrent: isCurrent,
                        blur: blurUpcoming && position > _currentIndex,
                        // A remote opens on the episode that is playing rather
                        // than on the close button.
                        autoFocus: isCurrent && isDPad,
                        onTap: () => _select(episode),
                        onMore: () => showItemActionsSheet(
                          context,
                          ref,
                          episode,
                          actions: episode.generateActions(context, ref, exclude: {ItemActions.play}),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.localized.close,
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// One pill per season, and one for the whole run, in a row that scrolls
/// when a long show has more of them than fit.
class _SeasonChips extends StatelessWidget {
  final Map<int, String> names;
  final int? selected;
  final ValueChanged<int?> onSelected;

  const _SeasonChips({required this.names, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        spacing: 8,
        children: [
          _Chip(label: context.localized.all, selected: selected == null, onTap: () => onSelected(null)),
          for (final entry in names.entries)
            _Chip(label: entry.value, selected: selected == entry.key, onTap: () => onSelected(entry.key)),
        ],
      ),
    );
  }
}

class _Chip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  State<_Chip> createState() => _ChipState();
}

class _ChipState extends State<_Chip> {
  @override
  void didUpdateWidget(_Chip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Selected from the list rather than by a tap on it - see
    // [_EpisodePanelState._stepSeason] - it may be off the end of the row.
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(999);
    return FocusButton(
      onTap: widget.onTap,
      borderRadius: radius,
      darkOverlay: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: widget.selected ? colors.primary : colors.onSurface.withValues(alpha: 0.10),
        ),
        child: Text(
          widget.label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: widget.selected ? colors.onPrimary : colors.onSurface,
                fontWeight: widget.selected ? FontWeight.w600 : null,
              ),
        ),
      ),
    );
  }
}

/// A still, the name, the length and a line or two of what happens - with
/// how far along it is under the still, and the one that is playing marked.
class _EpisodeTile extends ConsumerWidget {
  final EpisodeModel episode;
  final FocusNode focusNode;
  final bool isCurrent;
  final bool blur;
  final bool autoFocus;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _EpisodeTile({
    required this.episode,
    required this.focusNode,
    required this.isCurrent,
    required this.blur,
    required this.autoFocus,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final played = episode.userData.played;
    final progress = episode.userData.progress;
    final muted = colors.onSurface.withValues(alpha: 0.6);
    final radius = BorderRadius.circular(10);

    final meta = isCurrent
        ? Text(
            context.localized.nowPlaying,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.primary, fontWeight: FontWeight.w600),
          )
        : Text(
            episode.overview.runTime?.humanize ?? "",
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: FocusButton(
        focusNode: focusNode,
        autoFocus: autoFocus,
        onTap: onTap,
        onLongPress: onMore,
        onSecondaryTapDown: (_) => onMore(),
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: isCurrent ? colors.primary.withValues(alpha: 0.14) : null,
          ),
          child: Row(
            children: [
              _Still(episode: episode, isCurrent: isCurrent, played: played, progress: progress, blur: blur),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${episode.episodeRange}. ${episode.name}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: played && !isCurrent ? muted : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    meta,
                    if (episode.overview.summary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.overview.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurface.withValues(alpha: 0.5)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Still extends StatelessWidget {
  final EpisodeModel episode;
  final bool isCurrent;
  final bool played;
  final double progress;
  final bool blur;

  const _Still({
    required this.episode,
    required this.isCurrent,
    required this.played,
    required this.progress,
    required this.blur,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 136,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: colors.surfaceContainerHighest,
            border: isCurrent ? Border.all(color: colors.primary, width: 2) : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: played && !isCurrent ? 0.55 : 1,
                child: FladderImage(
                  image: episode.images?.primary,
                  blurOnly: blur,
                  decodeHeight: 160,
                  placeHolder: Icon(Icons.local_movies_outlined, color: colors.onSurface.withValues(alpha: 0.3)),
                ),
              ),
              if (played && !isCurrent)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded, size: 12, color: colors.onPrimary),
                  ),
                ),
              if (!played && progress > 0)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: progress / 100,
                    color: colors.primary,
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
