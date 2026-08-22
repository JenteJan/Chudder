import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/settings/home_settings_model.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/home_settings_provider.dart';
import 'package:fladder/screens/shared/media/carousel_banner.dart';
import 'package:fladder/screens/shared/media/detailed_banner.dart';
import 'package:fladder/screens/shared/media/media_banner.dart';
import 'package:fladder/screens/shared/media/tv_slider_banner.dart';

class HomeBannerWidget extends ConsumerWidget {
  final List<ItemBaseModel> posters;
  final Function(ItemBaseModel selected) onSelect;

  const HomeBannerWidget({
    required this.posters,
    required this.onSelect,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannerType = ref.watch(homeSettingsProvider.select((value) => value.homeBanner));
    // The row the dashboard opens with was the one thing on the screen that
    // ignored the poster size. Scaled before the clamp it still did: any window
    // taller than about 625 was already over the ceiling, so every setting came
    // out at 375. The setting scales what the clamp allows instead.
    final posterSize = ref.watch(clientSettingsProvider.select((value) => value.posterSize));
    final maxHeight = (MediaQuery.sizeOf(context).shortestSide * 0.6).clamp(125.0, 375.0) * posterSize;

    return switch (bannerType) {
      HomeBanner.carousel => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CarouselBanner(
              items: posters,
              maxHeight: maxHeight,
            ),
            const SizedBox(height: 24)
          ],
        ),
      HomeBanner.banner => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: MediaBanner(
            items: posters,
            maxHeight: maxHeight,
          ),
        ),
      HomeBanner.detailedBanner => DetailedBanner(
          posters: posters,
          onSelect: onSelect,
        ),
      HomeBanner.tvSliderBanner => TVSliderBanner(
          items: posters,
          onSelect: onSelect,
          maxHeight: maxHeight,
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
