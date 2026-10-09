import 'dart:convert';

import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:meta/meta.dart';

/// A user-editable override of a bundled script, stored in the encrypted
/// database.
///
/// The override is keyed by the script's relative path ([id] == path, e.g.
/// `modules/60_firewall.sh`); the bundled asset is the immutable original.
/// The override is always the version actually uploaded/run (spec §6.3,
/// RF-09, RF-10). An override is never "trusted" — its [contentHash] is
/// surfaced to the user so they stay aware of what is actually executed
/// (spec §8.6).
@immutable
class UserScript {
  /// Creates a [UserScript] with an already-computed [contentHash].
  ///
  /// Used when rebuilding from storage; for new versions prefer
  /// [UserScript.fromContent] so the hash cannot drift from the content.
  const UserScript({
    required this.id,
    required this.content,
    required this.contentHash,
    required this.createdAt,
  });

  /// Creates a [UserScript] for [content], computing its SHA-256 hash.
  factory UserScript.fromContent({
    required String id,
    required String content,
    required DateTime createdAt,
  }) {
    return UserScript(
      id: id,
      content: content,
      contentHash: sha256Hex(utf8.encode(content)),
      createdAt: createdAt,
    );
  }

  /// The overridden script's relative path (e.g. `modules/60_firewall.sh`).
  final String id;

  /// The raw bash script content.
  final String content;

  /// Lowercase hexadecimal SHA-256 digest of [content].
  final String contentHash;

  /// When this script version was saved.
  final DateTime createdAt;

  @override
  bool operator ==(Object other) {
    return other is UserScript &&
        other.id == id &&
        other.content == content &&
        other.contentHash == contentHash &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(id, content, contentHash, createdAt);
}
