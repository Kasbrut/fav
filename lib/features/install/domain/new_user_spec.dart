import 'package:meta/meta.dart';

/// Specification for a non-root user to be created on the server.
///
/// This object holds a plaintext [password]: it lives only in memory for the
/// duration of an operation and must never be persisted or logged
/// during provisioning.
@immutable
class NewUserSpec {
  /// Creates a [NewUserSpec].
  const NewUserSpec({required this.username, required this.password});

  /// Username of the new non-root user.
  final String username;

  /// Plaintext password for the new user. Never persist or log this value.
  final String password;

  /// Returns a copy of this spec with the given fields replaced.
  NewUserSpec copyWith({String? username, String? password}) {
    return NewUserSpec(
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NewUserSpec &&
        other.username == username &&
        other.password == password;
  }

  @override
  int get hashCode => Object.hash(username, password);

  @override
  String toString() {
    // The password is redacted so it cannot leak through logs or errors.
    return 'NewUserSpec(username: $username, password: <redacted>)';
  }
}
