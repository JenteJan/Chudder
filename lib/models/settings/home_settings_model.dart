import 'package:flutter/material.dart';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:chudder/models/settings/arguments_model.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/localization_helper.dart';

part 'home_settings_model.freezed.dart';
part 'home_settings_model.g.dart';

@Freezed(copyWith: true)
abstract class HomeSettingsModel with _$HomeSettingsModel {
  const HomeSettingsModel._();

  factory HomeSettingsModel({
    @Default({...LayoutMode.values}) Set<LayoutMode> screenLayouts,
    @Default({...ViewSize.values}) Set<ViewSize> layoutStates,
    @Default(HomeBanner.detailedBanner) HomeBanner homeBanner,
    @Default(HomeCarouselSettings.combined) HomeCarouselSettings carouselSettings,
    @Default(HomeNextUp.combined) HomeNextUp nextUp,
    @Default(HomeContinueArt.posters) HomeContinueArt continueArt,
    @Default(true) bool cardPreviews,
  }) = _HomeSettingsModel;

  static HomeSettingsModel defaultModel() {
    return HomeSettingsModel(
      homeBanner: leanBackMode ? HomeBanner.tvSliderBanner : HomeBanner.detailedBanner,
    );
  }

  factory HomeSettingsModel.fromJson(Map<String, dynamic> json) => _$HomeSettingsModelFromJson(json);
}

T selectAvailableOrSmaller<T>(T value, Set<T> availableOptions, List<T> allOptions) {
  if (availableOptions.contains(value)) {
    return value;
  }

  int index = allOptions.indexOf(value);

  for (int i = index - 1; i >= 0; i--) {
    if (availableOptions.contains(allOptions[i])) {
      return allOptions[i];
    }
  }

  return availableOptions.first;
}

enum HomeBanner {
  hide,
  carousel,
  banner,
  detailedBanner,
  tvSliderBanner;

  const HomeBanner();

  String label(BuildContext context) => switch (this) {
        HomeBanner.hide => context.localized.hide,
        HomeBanner.carousel => context.localized.homeBannerCarousel,
        HomeBanner.banner => context.localized.homeBannerSlideshow,
        HomeBanner.detailedBanner => context.localized.homeBannerDetailed,
        HomeBanner.tvSliderBanner => context.localized.homeBannerTV,
      };
}

/// What the banner at the top of the home page shows.
enum HomeCarouselSettings {
  nextUp,

  /// Kept so a stored choice still reads; offered as [combined], which is
  /// Continue watching however the rows are set.
  cont,
  combined,
  recentlyAdded,
  random,
  favourites,
  ;

  const HomeCarouselSettings();

  /// The choices offered, in the order they are offered.
  static const offered = [combined, nextUp, recentlyAdded, random, favourites];

  /// Whether this is Continue watching, whatever it was stored as.
  bool get isContinue => this == cont || this == combined;

  String label(BuildContext context) => switch (this) {
        HomeCarouselSettings.nextUp => context.localized.nextUp,
        HomeCarouselSettings.cont || HomeCarouselSettings.combined => context.localized.dashboardContinueWatching,
        HomeCarouselSettings.recentlyAdded => context.localized.recentlyAdded,
        HomeCarouselSettings.random => context.localized.random,
        HomeCarouselSettings.favourites => context.localized.favorites,
      };

  /// The name of the banner's row, where it has one.
  String rowLabel(BuildContext context) => switch (this) {
        HomeCarouselSettings.random => context.localized.discover,
        _ => label(context),
      };
}

enum HomeNextUp {
  off,
  nextUp,
  cont,
  combined,
  separate,
  ;

  const HomeNextUp();

  String label(BuildContext context) => switch (this) {
        HomeNextUp.off => context.localized.hide,
        HomeNextUp.nextUp => context.localized.nextUp,
        HomeNextUp.cont => context.localized.settingsContinue,
        HomeNextUp.combined => context.localized.combined,
        HomeNextUp.separate => context.localized.separate,
      };
}

/// What the Continue watching and Next up cards show: the poster, or a wide
/// picture of the thing itself - the frame you stopped at, where there is one.
enum HomeContinueArt {
  posters,
  screenshots,
}
