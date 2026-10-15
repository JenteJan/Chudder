// Stand-ins for what the d-pad tests open screens with: a signed-in
// administrator, and a player that is never started.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';

class AdminUser extends User {
  @override
  AccountModel? build() => AccountModel(
        name: 'admin',
        id: 'user',
        avatar: '',
        lastUsed: DateTime(2026),
        credentials: CredentialsModel.internal(),
        policy: const UserPolicy(
          isAdministrator: true,
          enableSubtitleManagement: true,
          enableCollectionManagement: true,
          authenticationProviderId: '',
          passwordResetProviderId: '',
        ),
      );
}

/// The player's notifier without its start-up: no audio service, no media
/// session, no native player.
class IdlePlayer extends VideoPlayerNotifier {
  IdlePlayer(super.ref);
}

List<Override> get playerFakes => [
      userProvider.overrideWith(AdminUser.new),
      videoPlayerProvider.overrideWith(IdlePlayer.new),
    ];
