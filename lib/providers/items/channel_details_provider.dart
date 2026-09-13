import 'package:chopper/chopper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';

import 'package:chudder/models/items/channel_model.dart';
import 'package:chudder/models/items/channel_program.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/service_provider.dart';

part 'channel_details_provider.g.dart';

@riverpod
class ChannelDetails extends _$ChannelDetails {
  JellyService get api => ref.read(jellyApiProvider);

  @override
  ChannelModel? build(String id) {
    return null;
  }

  Future<void> fetchDetails(String id) async {
    // The guide for this channel is asked for by its id, so it goes out with
    // the channel rather than after it. Not while offline, where the channel
    // itself decides whether anything is asked of the server at all.
    Future<Response<BaseItemDtoQueryResult>> programs() => api.liveTvChannelPrograms(
          channelIds: [id],
          minEndDate: DateTime.now(),
        );
    final programsFuture = ref.read(offlineStateProvider) ? null : (programs()..ignore());

    final channelResponse = await api.usersUserIdItemsItemIdGet(itemId: id);
    if (channelResponse.body == null || channelResponse.body is! ChannelModel) return;
    final channelModel = channelResponse.bodyOrThrow as ChannelModel;
    state = channelModel;

    final programsResponse = await (programsFuture ?? programs());

    state = state?.copyChannelWith(
      programs: programsResponse.body?.items?.map((e) => ChannelProgram.fromBaseDto(e, ref)).toList() ?? [],
    );
  }
}
