import 'dart:async';
import 'dart:convert';

import 'package:chopper/chopper.dart';

import 'seerr_models.dart';

class SeerrJsonConverter extends JsonConverter {
  const SeerrJsonConverter();

  static Map<Type, Function> get _typeDeserializers => {
        SeerrStatus: SeerrStatus.fromJson,
        SeerrUserModel: SeerrUserModel.fromJson,
        SeerrUserSettings: SeerrUserSettings.fromJson,
        SeerrSonarrServer: SeerrSonarrServer.fromJson,
        SeerrSonarrServerResponse: SeerrSonarrServerResponse.fromJson,
        SeerrRadarrServer: SeerrRadarrServer.fromJson,
        SeerrRadarrServerResponse: SeerrRadarrServerResponse.fromJson,
        SeerrServiceProfile: SeerrServiceProfile.fromJson,
        SeerrServiceTag: SeerrServiceTag.fromJson,
        SeerrRootFolder: SeerrRootFolder.fromJson,
        SeerrMovieDetails: SeerrMovieDetails.fromJson,
        SeerrTvDetails: SeerrTvDetails.fromJson,
        SeerrSeasonDetails: SeerrSeasonDetails.fromJson,
        SeerrEpisode: SeerrEpisode.fromJson,
        SeerrUserQuota: SeerrUserQuota.fromJson,
        SeerrQuotaEntry: SeerrQuotaEntry.fromJson,
        SeerrGenre: SeerrGenre.fromJson,
        SeerrSeason: SeerrSeason.fromJson,
        SeerrMediaInfoSeason: SeerrMediaInfoSeason.fromJson,
        SeerrMediaInfo: SeerrMediaInfo.fromJson,
        SeerrExternalIds: SeerrExternalIds.fromJson,
        SeerrRequestsResponse: SeerrRequestsResponse.fromJson,
        SeerrMediaRequest: SeerrMediaRequest.fromJson,
        SeerrPageInfo: SeerrPageInfo.fromJson,
        SeerrCreateRequestBody: SeerrCreateRequestBody.fromJson,
        SeerrMedia: SeerrMedia.fromJson,
        SeerrMediaResponse: SeerrMediaResponse.fromJson,
        SeerrDiscoverResponse: SeerrDiscoverResponse.fromJson,
        SeerrUsersResponse: SeerrUsersResponse.fromJson,
        SeerrAuthLocalBody: SeerrAuthLocalBody.fromJson,
        SeerrAuthJellyfinBody: SeerrAuthJellyfinBody.fromJson,
        SeerrGenreResponse: SeerrGenreResponse.fromJson,
        SeerrCombinedCreditsResponse: SeerrCombinedCreditsResponse.fromJson,
        SeerrWatchProvider: SeerrWatchProvider.fromJson,
        SeerrWatchProviderRegion: SeerrWatchProviderRegion.fromJson,
        SeerrCertificationsResponse: SeerrCertificationsResponse.fromJson,
        SeerrSearchCompanyResponse: SeerrSearchCompanyResponse.fromJson,
        SeerrCompany: SeerrCompany.fromJson,
        SeerrContentRating: SeerrContentRating.fromJson,
        SeerrRatingsResponse: SeerrRatingsResponse.fromJson,
        SeerrRtRating: SeerrRtRating.fromJson,
        SeerrImdbRating: SeerrImdbRating.fromJson,
      };

  @override
  FutureOr<Response<ResultType>> convertResponse<ResultType, Item>(
    Response response,
  ) async {
    if (response.bodyBytes.isEmpty) return response.copyWith();

    try {
      // From the bytes, once. `bodyString` and `body` are each a decode of
      // the whole response, and the latter guesses latin-1 when the server
      // names no charset - which is how non-ASCII titles arrived garbled.
      final dynamic decodedBody = jsonDecode(utf8.decode(response.bodyBytes));

      final dynamic convertedData = _decodeInternal<Item>(decodedBody);

      if (convertedData is! ResultType) {
        throw Exception('Type Mismatch: Expected $ResultType but got ${convertedData.runtimeType}. '
            'Check if $Item is registered in _typeDeserializers.');
      }

      return response.copyWith<ResultType>(body: convertedData);
    } catch (e, stackTrace) {
      print('Serialization Error: $e\n$stackTrace');
      return response.copyWith<ResultType>(body: null, bodyError: e);
    }
  }

  dynamic _decodeInternal<Item>(dynamic data) {
    if (data is List) {
      return data.map((item) => _decodeInternal<Item>(item)).toList().cast<Item>();
    }

    if (data is Map<String, dynamic>) {
      final factory = _typeDeserializers[Item];
      if (factory != null) {
        return factory(data);
      }
      return data;
    }

    return data;
  }
}
