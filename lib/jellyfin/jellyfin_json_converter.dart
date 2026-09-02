import 'dart:async';

import 'package:chopper/chopper.dart' as chopper;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// The generated converter, minus one full decode of every body.
///
/// The generated one asks `bodyString.isEmpty` to catch a 204, and
/// `bodyString` is not a field but a decode of the whole response - which the
/// JSON step then does again. The bytes answer the same question for free.
class FladderJsonConverter extends chopper.JsonConverter {
  const FladderJsonConverter();

  @override
  FutureOr<chopper.Response<ResultType>> convertResponse<ResultType, Item>(
    chopper.Response response,
  ) async {
    if (response.bodyBytes.isEmpty) {
      return chopper.Response(response.base, null, error: response.error);
    }

    if (ResultType == String) {
      return response.copyWith();
    }

    if (ResultType == DateTime) {
      return response.copyWith(
        body: DateTime.parse((response.body as String).replaceAll('"', '')) as ResultType,
      );
    }

    final jsonRes = await super.convertResponse(response);
    return jsonRes.copyWith<ResultType>(
      body: $jsonDecoder.decode<Item>(jsonRes.body) as ResultType,
    );
  }
}
