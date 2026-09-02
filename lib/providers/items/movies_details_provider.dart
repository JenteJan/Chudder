import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:logging/logging.dart' as logging;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/related_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

part 'movies_details_provider.g.dart';

@riverpod
class MovieDetails extends _$MovieDetails {
  late final JellyService api = ref.read(jellyApiProvider);

  @override
  MovieModel? build(String arg) => null;

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    try {
      if (item is MovieModel && state == null) {
        // Called from a page's initState, which is mid-build - and Riverpod
        // refuses a write during build. One microtask later the frame is
        // done; the page paints its own copy of the item until then.
        await Future<void>.microtask(() {});
        state ??= item;
      }
      // The item, its extras and its related row share nothing, so they are
      // asked for together. The page paints the item the moment it lands and
      // the rows under it fill in after; they used to queue, six deep, with
      // the three Seerr requests at the back.
      final itemRequest = api.usersUserIdItemsItemIdGet(itemId: item.id);
      final specialFeaturesRequest = api
          .itemsItemIdSpecialFeaturesGet(itemId: item.id)
          .then<List<BaseItemDto>>((value) => value.body ?? [])
          .catchError((Object e, StackTrace s) {
        log("Failed to get special features for movie id ${item.id} due to $e",
            level: logging.Level.WARNING.value, error: e, stackTrace: s);
        return <BaseItemDto>[];
      });
      final relatedRequest = ref.read(relatedUtilityProvider).relatedContent(item.id);

      final response = await itemRequest;
      if (response.body == null) return null;
      MovieModel newState = (response.bodyOrThrow as MovieModel).copyWith(
        related: state?.related ?? const [],
        seerrRelated: state?.seerrRelated ?? const [],
        seerrRecommended: state?.seerrRecommended ?? const [],
      );

      state = newState;

      final specialFeatures = await specialFeaturesRequest;
      final related = await relatedRequest;
      final List<SpecialFeatureModel> specialFeatureModel =
          SpecialFeatureModel.specialFeaturesFromDto(specialFeatures, ref).toList();

      newState = newState.copyWith(
        related: related.body,
        specialFeatures: specialFeatureModel,
      );
      state = newState;

      final seerrCreds = ref.read(userProvider)?.seerrCredentials;
      final tmdbId = newState.tmdbId;
      if (seerrCreds?.isConfigured == true && tmdbId != null) {
        final seerr = ref.read(seerrApiProvider);
        final seerrResults = await Future.wait<Object?>([
          seerr.discoverRelatedMovies(tmdbId: tmdbId),
          seerr.discoverRecommendedMovies(tmdbId: tmdbId),
          seerr.fetchDashboardPosterFromIds(
            tmdbId: tmdbId,
            mediaType: SeerrMediaType.movie,
          ),
        ]);
        final seerrRelated = seerrResults[0] as List<SeerrDashboardPosterModel>;
        final seerrRecommended = seerrResults[1] as List<SeerrDashboardPosterModel>;
        final seerrPoster = seerrResults[2] as SeerrDashboardPosterModel?;

        String? seerrUrl;
        final status = seerrPoster?.mediaInfo?.mediaStatus;
        if (status != SeerrMediaStatus.unknown) {
          final seerrServerUrl = ref.read(userProvider.select((value) => value?.seerrCredentials?.serverUrl));
          seerrUrl = '${seerrServerUrl}movie/$tmdbId';
        }

        state = newState.copyWith(
          seerrRelated: seerrRelated,
          seerrRecommended: seerrRecommended,
          overview: state?.overview.copyWith(
            seerrUrl: seerrUrl,
          ),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  void setMediaStreamHelper(MediaStreamsModel changed) {
    state = state?.copyWith(mediaStreams: changed);
  }
}
