import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/settings/arguments_model.dart';

final argumentsStateProvider = StateProvider<ArgumentsModel>((ref) => ArgumentsModel());
