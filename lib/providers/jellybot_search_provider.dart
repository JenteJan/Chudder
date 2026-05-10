import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';

part 'jellybot_search_provider.g.dart';

@riverpod
Future<List<IProvider>> jellybotProviders(Ref ref) async {
  final api = ref.watch(jellybotApiProvider);
  final response = await api.apiProvidersGet(searchEnabled: true);
  if (!response.isSuccessful || response.body == null) {
    return const <IProvider>[];
  }
  return response.body!;
}
