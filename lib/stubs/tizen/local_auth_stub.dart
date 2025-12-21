// Stub for local_auth on Tizen
// TVs don't have biometric authentication

class LocalAuthentication {
  Future<bool> get isDeviceSupported => Future.value(false);

  Future<List<BiometricType>> getAvailableBiometrics() async {
    return [];
  }

  Future<bool> authenticate({
    required String localizedReason,
    bool useErrorDialogs = true,
    bool stickyAuth = false,
    bool sensitiveTransaction = true,
    bool biometricOnly = false,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    return false;
  }

  Future<void> stopAuthentication() async {}
}

enum BiometricType {
  face,
  fingerprint,
  iris,
  strong,
  weak,
}

class AuthenticationOptions {
  final bool useErrorDialogs;
  final bool stickyAuth;
  final bool sensitiveTransaction;
  final bool biometricOnly;

  const AuthenticationOptions({
    this.useErrorDialogs = true,
    this.stickyAuth = false,
    this.sensitiveTransaction = true,
    this.biometricOnly = false,
  });
}
