import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/seerr/seerr_models.dart';

part 'seerr_user_provider.g.dart';

// Kept alive: a service that is read and held, not watched. Riverpod 3
// will not let a disposed provider's ref make the next request.
@Riverpod(keepAlive: true)
class SeerrUser extends _$SeerrUser {
  @override
  SeerrUserModel? build() {
    _fetchUser();
    return null;
  }

  Future<void> _fetchUser() async {
    // Out of reach it simply stays unknown, as it does when not signed in;
    // opening the profile settings offline used to raise an unhandled error.
    try {
      final api = ref.read(seerrApiProvider);
      final response = await api.me();
      if (response.isSuccessful && response.body is SeerrUserModel) {
        state = response.body as SeerrUserModel;
      }
    } catch (_) {}
  }

  Future<SeerrUserModel?> refreshUser() async {
    final api = ref.read(seerrApiProvider);
    final response = await api.me();
    if (response.isSuccessful && response.body is SeerrUserModel) {
      state = response.body as SeerrUserModel;
      return response.body as SeerrUserModel;
    }
    return null;
  }

  void clearUser() {
    state = null;
  }
}
