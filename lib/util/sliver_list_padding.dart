import 'package:flutter/material.dart';

import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';

class DefaultSliverBottomPadding extends StatelessWidget {
  const DefaultSliverBottomPadding({super.key});

  @override
  Widget build(BuildContext context) {
    // The padding carries the phone's bottom bar now, so a phone needs no
    // more room than anything else.
    return SliverPadding(padding: EdgeInsets.only(bottom: 60 + MediaQuery.paddingOf(context).bottom));
  }
}

class DefaultSliverTopBadding extends StatelessWidget {
  const DefaultSliverTopBadding({super.key});

  @override
  Widget build(BuildContext context) {
    return (AdaptiveLayout.viewSizeOf(context) == ViewSize.phone)
        ? const SliverToBoxAdapter()
        : SliverPadding(
            padding:
                EdgeInsets.only(top: MediaQuery.of(context).padding.top + AdaptiveLayout.of(context).statusBarHeight),
          );
  }
}
