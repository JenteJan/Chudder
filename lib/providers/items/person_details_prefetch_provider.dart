import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/person_model.dart';
import 'package:chudder/providers/api_provider.dart';

/// A person's page, asked for while the pointer is still on their face.
///
/// The film prefetch's counterpart for people. A face in a cast row carries a
/// name and a picture and nothing else, so the page it opens asks for three
/// things - the person, their films and their shows - and the credits are the
/// slow part on a big library. Asked for on hover or focus, they are usually
/// back by the time the page is pushed.
///
/// A page that was open before is kept too, so going back to someone shows
/// them straight away while the page asks again underneath.
final personDetailsPrefetchProvider = Provider<PersonDetailsPrefetch>(PersonDetailsPrefetch.new);

/// The three requests a person's page waits on, all started at once.
class PersonRequests {
  final Future<Response<ItemBaseModel>> person;
  final Future<List<ItemBaseModel>?> movies;
  final Future<List<ItemBaseModel>?> series;

  PersonRequests({required this.person, required this.movies, required this.series});
}

class PersonDetailsPrefetch {
  PersonDetailsPrefetch(this.ref);

  final Ref ref;

  final Map<String, PersonRequests> _inFlight = {};
  final Map<String, PersonModel> _byId = {};

  /// The last page shown for this person, or null. Never waits.
  PersonModel? of(String? id) => id == null ? null : _byId[id];

  /// Remembers what a page ended up showing, for the next time it opens.
  void remember(PersonModel person) => _byId[person.id] = person;

  /// The requests on their way for this person - joined if [prefetch] already
  /// started them, started here if not. Only ever requests still in flight:
  /// an answer from earlier is [of]'s, and the page asks again over it.
  PersonRequests request(String id) {
    final existing = _inFlight[id];
    if (existing != null) return existing;

    final api = ref.read(jellyApiProvider);
    Future<List<ItemBaseModel>?> credits(BaseItemKind kind) async {
      final response = await api.itemsGet(
        personIds: [id],
        limit: 25,
        sortBy: [ItemSortBy.premieredate, ItemSortBy.communityrating, ItemSortBy.sortname, ItemSortBy.productionyear],
        sortOrder: [SortOrder.descending],
        recursive: true,
        fields: [
          ItemFields.primaryimageaspectratio,
        ],
        includeItemTypes: [kind],
      );
      return response.body?.items;
    }

    final requests = PersonRequests(
      person: api.usersUserIdItemsItemIdGet(itemId: id),
      movies: credits(BaseItemKind.movie),
      series: credits(BaseItemKind.series),
    );
    // Nobody may be waiting on these yet; a failure is the page's to report.
    requests.person.ignore();
    requests.movies.ignore();
    requests.series.ignore();

    _inFlight[id] = requests;
    Future.wait([requests.person, requests.movies, requests.series]).whenComplete(() => _inFlight.remove(id)).ignore();
    return requests;
  }

  /// Starts the requests ahead of being asked. Does nothing if they are
  /// already on their way, or if the page has someone to show already - it
  /// asks again itself once it is open.
  void prefetch(String? id) {
    if (id == null || id.isEmpty || _byId.containsKey(id)) return;
    request(id);
  }
}
