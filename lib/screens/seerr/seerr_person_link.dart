import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/person_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/items/person_details_provider.dart';
import 'package:chudder/screens/details_screens/person_detail_screen.dart';
import 'package:chudder/util/external_links.dart';

/// Opens someone from a Seerr page on their page in the library.
///
/// Seerr's people are TMDB's, known by TMDB ids the server has never heard of,
/// so the face that was pressed is looked up by name and matched by TMDB id -
/// or, where the server has no TMDB id for them, by being the only one of that
/// name. Anyone the library does not have gets their page from Seerr instead,
/// the way a film the library does not have opens on Discover.
Future<void> openSeerrPerson(BuildContext context, WidgetRef ref, Person person) async {
  final response = await ref.read(jellyApiProvider).personsGet(searchTerm: person.name, limit: 20);
  if (!context.mounted) return;

  final match = matchLibraryPerson(person, response.body?.whereType<PersonModel>() ?? const []);

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => PersonDetailScreen(
        // The face that was pressed stands in until the page's own arrives.
        person: match != null
            ? Person(id: match.id, name: match.name, image: match.images?.primary ?? person.image)
            : Person(id: seerrPersonId(person.id), name: person.name, image: person.image),
      ),
    ),
  );
}

/// Which of the library's people [person] - one of TMDB's - is: the one with
/// the same TMDB id, or failing that the only one of that name the server has
/// no TMDB id for. Two of a name without ids could be anyone, so neither.
PersonModel? matchLibraryPerson(Person person, Iterable<PersonModel> candidates) {
  for (final candidate in candidates) {
    if (candidate.tmdbIdString == person.id) return candidate;
  }
  final name = person.name.toLowerCase();
  final sameName = candidates.where((candidate) => candidate.name.toLowerCase() == name).toList();
  if (sameName.length == 1 && sameName.first.tmdbIdString == null) return sameName.first;
  return null;
}
