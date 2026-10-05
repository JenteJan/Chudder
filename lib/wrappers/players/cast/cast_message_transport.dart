/// A change in the link between this sender and the receiver, reported by the
/// transport that owns the link (the Cast SDK's session listener, the desktop
/// socket, the Cast Web Sender's session state).
enum CastLinkEvent {
  /// The link dropped for a moment (network blip, app frozen in the
  /// background) and the transport is trying to get it back. Nothing is torn
  /// down: the receiver keeps playing meanwhile.
  suspended,

  /// The link is back after [suspended]. The receiver may have moved on in the
  /// meantime, so its state has to be asked for again.
  resumed,

  /// The session is over: the receiver app closed, another app took the
  /// device, or the link could not be restored.
  ended,
}

/// The transport for talking to the Jellyfin Cast receiver over its custom
/// namespace — the *only* thing that differs between the native (mobile),
/// desktop and web Cast senders. All the receiver-control logic (PlayNow
/// retry, position ticker, message → state, track-switch restart) is shared in
/// `JellyfinReceiverPlayer`.
abstract class CastMessageTransport {
  /// Raw JSON messages received from the receiver on the Jellyfin namespace.
  Stream<String> get messages;

  /// Suspensions, resumptions and the end of the session.
  Stream<CastLinkEvent> get linkEvents;

  /// Sends a JSON envelope to the receiver on the Jellyfin namespace.
  Future<void> sendMessage(String json);

  /// Sets the Cast device volume (0.0–1.0). The receiver protocol's own volume
  /// commands are stubs, so volume goes through the SDK / session.
  Future<void> setVolume(double level);

  /// Ends this sender's part in the session and releases the transport.
  ///
  /// With [stopReceiver] the receiver app is closed as well — the user chose to
  /// stop casting. Without it only this sender goes: the TV keeps playing,
  /// which is what leaving the app must do (Google's sender checklist), and
  /// what another sender that took the device over needs.
  Future<void> close({required bool stopReceiver});
}
