import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/item_details_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';

/// The hero tag of the poster that was tapped to open this page, for whatever
/// inside it wants to be the other end of that flight.
///
/// Passed down rather than through [ItemBaseModel.detailScreenWidget], which is
/// a getter with nowhere to put an argument, and read by [DetailScaffold] —
/// which is the thing that actually knows where the artwork lands.
class DetailHeroTag extends InheritedWidget {
  final Object? tag;
  const DetailHeroTag({required this.tag, required super.child, super.key});

  static Object? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<DetailHeroTag>()?.tag;

  @override
  bool updateShouldNotify(DetailHeroTag oldWidget) => tag != oldWidget.tag;
}

@RoutePage()
class DetailsScreen extends ConsumerStatefulWidget {
  final String id;
  final ItemBaseModel? item;
  final Object? tag;
  const DetailsScreen({
    @QueryParam() this.id = '',
    this.item,
    this.tag,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  /// The page itself straight away when we were handed the item, rather than a
  /// frame of spinner first.
  ///
  /// Not a nicety. The hero flight from the poster looks for its far end in
  /// this subtree, in a post-frame callback of the very frame the route is
  /// pushed - and post-frame callbacks run before microtasks do. A page that
  /// arrives one microtask late has no Hero in it yet when that search happens,
  /// so no flight is ever started. Only a bare link, with an id and nothing
  /// else, has to wait.
  late Widget currentWidget = widget.item?.detailScreenWidget ??
      const Center(
        key: Key("progress-indicator"),
        child: CircularProgressIndicator(strokeCap: StrokeCap.round),
      );

  @override
  void didUpdateWidget(covariant DetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb) {
      updateWidget();
    }
  }

  @override
  void initState() {
    super.initState();
    // With an item in hand the page is already built above; only a bare link
    // has to go and find out what it points at.
    if (widget.item == null) updateWidget();
  }

  Future<void> updateWidget() async {
    if (widget.item != null) {
      if (mounted) {
        setState(() {
          currentWidget = widget.item!.detailScreenWidget;
        });
      }
      return;
    }
    final response = await ref.read(itemDetailsProvider.notifier).fetchDetails(widget.id);
    if (!context.mounted) return;
    if (response != null) {
      setState(() {
        currentWidget = response.detailScreenWidget;
      });
    } else {
      const DashboardRoute().navigate(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Just the page, on an opaque ground so the spinner has something to sit on
    // while a cold link is being resolved.
    //
    // What used to be here was a poster flying in from wherever you tapped and
    // a second-long cross-fade over the top of it. The fade went first; the
    // flight only looked worse without it to hide behind. Between them they
    // were also the most expensive thing happening at exactly the moment the
    // page was building its rows - the poster was a full-size image decoded on
    // every navigation and then covered up by an opaque page.
    return ColoredBox(
      key: Key(widget.id),
      color: Theme.of(context).colorScheme.surface,
      child: DetailHeroTag(
        tag: widget.tag,
        child: currentWidget,
      ),
    );
  }
}
