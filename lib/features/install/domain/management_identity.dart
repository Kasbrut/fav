import 'package:fav/features/install/domain/new_user_spec.dart';
import 'package:meta/meta.dart';

/// The user account the app manages the server as during and after install.
///
/// For a root login the app creates a non-root user and manages the server as
/// that user; for a non-root login it manages the server as the login user
/// itself. SSH hardening (disable root SSH + disable password auth) verifies
/// and operates against this identity, regardless of which case applies.
///
/// Holds a plaintext [password]: it lives only in memory for the duration of an
/// operation and must never be persisted or logged.
@immutable
class ManagementIdentity {
  /// Creates a [ManagementIdentity].
  const ManagementIdentity({
    required this.username,
    required this.password,
    required this.createdByUs,
  });

  /// Resolves the identity from the install inputs: the created [newUser] when
  /// present (root login), otherwise the login user ([loginUsername] /
  /// [loginPassword], a non-root sudoer).
  factory ManagementIdentity.resolve({
    required NewUserSpec? newUser,
    required String loginUsername,
    required String loginPassword,
  }) {
    if (newUser != null) {
      return ManagementIdentity(
        username: newUser.username,
        password: newUser.password,
        createdByUs: true,
      );
    }
    return ManagementIdentity(
      username: loginUsername,
      password: loginPassword,
      createdByUs: false,
    );
  }

  /// The account username.
  final String username;

  /// The account password (login + sudo). Never persist or log this value.
  final String password;

  /// Whether FAV created this user during the install (root login) or it is the
  /// pre-existing login user (non-root login).
  final bool createdByUs;

  @override
  String toString() =>
      'ManagementIdentity(username: $username, password: <redacted>, '
      'createdByUs: $createdByUs)';
}
