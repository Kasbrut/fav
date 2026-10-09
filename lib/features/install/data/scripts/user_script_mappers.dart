import 'package:fav/features/install/domain/user_script.dart';

/// Serializes [script] to a storage map.
Map<String, Object?> userScriptToMap(UserScript script) {
  return {
    'id': script.id,
    'content': script.content,
    'contentHash': script.contentHash,
    'createdAt': script.createdAt.toIso8601String(),
  };
}

/// Reconstructs a [UserScript] from a storage map.
UserScript userScriptFromMap(Map<dynamic, dynamic> map) {
  return UserScript(
    id: map['id'] as String,
    content: map['content'] as String,
    contentHash: map['contentHash'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
