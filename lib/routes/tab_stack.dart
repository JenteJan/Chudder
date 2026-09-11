import 'package:flutter/widgets.dart';

import 'package:auto_route/auto_route.dart';

/// What each of Home's tabs is: a stack of pages of its own.
///
/// Everything opened from a tab - a film, the actor in it, the library that
/// actor's next film sits in - goes on that tab's stack, and stays there while
/// you look at another tab; coming back finds the page you left. Only going
/// back, or pressing the tab you are already on, takes pages off it.
///
/// A navigator of its own, and so a hero controller of its own: one controller
/// can only drive one navigator, and the flight from a poster to its page is
/// run by the navigator the page is pushed on.
class TabStack extends StatefulWidget {
  const TabStack({super.key});

  @override
  State<TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<TabStack> {
  final HeroController _heroController = HeroController();

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HeroControllerScope(
        controller: _heroController,
        child: const AutoRouter(),
      );
}

/// The page of every tab: the tabs differ only in their name and in the pages
/// under them, and the route config holds both.
Widget buildTabStack(RouteData _) => const TabStack();
