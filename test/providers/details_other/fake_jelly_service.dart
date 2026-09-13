import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_provider.dart';

class FakeCall {
  FakeCall(this.member, this.args);
  final String member;
  final Map<Symbol, dynamic> args;
  final Completer<dynamic> completer = Completer<dynamic>();

  T? arg<T>(String name) => args[Symbol(name)] as T?;
}

/// A JellyService whose requests are held until the test answers them, so a
/// test can see what was asked for before anything came back.
class FakeJellyService implements JellyService {
  final List<FakeCall> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll('Symbol("', '').replaceAll('")', '');
    final call = FakeCall(name, invocation.namedArguments);
    calls.add(call);
    return switch (name) {
      'itemsGet' => call.completer.future.then((value) => value as Response<ServerQueryResult>),
      'usersUserIdItemsItemIdGet' => call.completer.future.then((value) => value as Response<ItemBaseModel>),
      'usersUserIdViewsGet' ||
      'itemsItemIdSimilarGet' =>
        call.completer.future.then((value) => value as Response<BaseItemDtoQueryResult>),
      'personsGet' => call.completer.future.then((value) => value as Response<List<ItemBaseModel>>),
      _ => super.noSuchMethod(invocation),
    };
  }

  Iterable<FakeCall> named(String member) => calls.where((call) => call.member == member);

  FakeCall itemGet() => named('usersUserIdItemsItemIdGet').first;

  FakeCall query({BaseItemKind? kind, bool Function(FakeCall call)? where}) => named('itemsGet').firstWhere((call) =>
      (kind == null || (call.arg<List<BaseItemKind>>('includeItemTypes')?.contains(kind) ?? false)) &&
      (where == null || where(call)));
}

class FakeJellyApi extends JellyApi {
  FakeJellyApi(this.service);
  final FakeJellyService service;
  @override
  JellyService build() => service;
}

class FakeOnline extends ConnectivityStatus {
  @override
  ConnectionState build() => ConnectionState.wifi;
}

class FakeNoUser extends User {
  @override
  AccountModel? build() => null;
}

Response<T> okResponse<T>(T body) => Response(http.Response('', 200), body);

ItemBaseModel fakeItem(String id, BaseItemKind type, {String? parentId, List<String>? artists, String? name}) =>
    ItemBaseModel.fromBaseDto(
      BaseItemDto(id: id, type: type, name: name ?? id, parentId: parentId, artists: artists),
      null,
    );

Response<ServerQueryResult> queryResult(List<ItemBaseModel> items, {int? total}) =>
    okResponse(ServerQueryResult(items: items, totalRecordCount: total ?? items.length));

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// A container whose JellyService is [service], online, signed out.
ProviderContainer fakeContainer(FakeJellyService service, [List<Override> extra = const []]) => ProviderContainer(
      overrides: [
        jellyApiProvider.overrideWith(() => FakeJellyApi(service)),
        connectivityStatusProvider.overrideWith(() => FakeOnline()),
        offlineStateProvider.overrideWithValue(false),
        userProvider.overrideWith(() => FakeNoUser()),
        ...extra,
      ],
    );
