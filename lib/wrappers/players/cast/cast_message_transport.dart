/// The transport for talking to the Jellyfin Cast receiver over its custom
/// namespace — the *only* thing that differs between the native (mobile) and
/// web Cast senders. All the receiver-control logic (PlayNow retry, position
/// ticker, message → state, track-switch restart) is shared in
/// `JellyfinReceiverPlayer`.
abstract class CastMessageTransport {
  /// Raw JSON messages received from the receiver on the Jellyfin namespace.
  Stream<String> get messages;

  /// Sends a JSON envelope to the receiver on the Jellyfin namespace.
  Future<void> sendMessage(String json);

  /// Sets the Cast device volume (0.0–1.0). The receiver protocol's own volume
  /// commands are stubs, so volume goes through the SDK / session.
  Future<void> setVolume(double level);

  /// Ends the session and releases the transport.
  Future<void> dispose();
}
