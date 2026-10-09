import 'package:meta/meta.dart';

/// Why the monitoring agent could not tell us the client's current state.
enum ClientLiveStatusUnknownReason {
  /// The agent's last snapshot is too old (timer stopped / service crashed).
  agentStale,

  /// SSH to the server failed; the snapshot could not be fetched.
  sshDown,

  /// The agent is not installed on this server.
  notInstalled,
}

/// Live status of a specific client peer (M15-T5), as derived from the
/// agent's snapshot + recent events.
@immutable
sealed class ClientLiveStatus {
  /// Const base constructor.
  const ClientLiveStatus();
}

/// The peer is currently online.
class ClientLiveStatusConnected extends ClientLiveStatus {
  /// Creates a [ClientLiveStatusConnected].
  const ClientLiveStatusConnected();
}

/// The peer was last seen at [serverTimestamp] (server clock).
class ClientLiveStatusLastSeen extends ClientLiveStatus {
  /// Creates a [ClientLiveStatusLastSeen].
  const ClientLiveStatusLastSeen(this.serverTimestamp);

  /// Server-side timestamp of the most recent online observation.
  final DateTime serverTimestamp;

  @override
  bool operator ==(Object other) =>
      other is ClientLiveStatusLastSeen &&
      other.serverTimestamp == serverTimestamp;

  @override
  int get hashCode => serverTimestamp.hashCode;
}

/// The peer is known to the server but has never been observed online.
class ClientLiveStatusNeverConnected extends ClientLiveStatus {
  /// Creates a [ClientLiveStatusNeverConnected].
  const ClientLiveStatusNeverConnected();
}

/// The live state is currently unknown ([reason] explains why).
class ClientLiveStatusUnknown extends ClientLiveStatus {
  /// Creates a [ClientLiveStatusUnknown].
  const ClientLiveStatusUnknown(this.reason);

  /// Why the status is unavailable.
  final ClientLiveStatusUnknownReason reason;

  @override
  bool operator ==(Object other) =>
      other is ClientLiveStatusUnknown && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}
