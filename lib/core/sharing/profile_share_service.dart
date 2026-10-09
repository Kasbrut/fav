import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posix/posix.dart' as posix;
import 'package:share_plus/share_plus.dart';

/// Restricts an exported profile to its owner on POSIX desktop systems.
Future<void> hardenExportedProfile(String path) async {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  try {
    posix.chmod(path, '600');
  } on Object {
    // Never leave an exported private key with broader permissions when
    // hardening fails. The UI reports the save as failed.
    try {
      await File(path).delete();
    } on Object {
      // Preserve the original hardening failure.
    }
    rethrow;
  }
}

/// Platform actions for the `ProfileResultScreen` — save the `.conf` to a
/// user-chosen file, share it via the OS sheet, copy it to the clipboard.
///
/// Surfaced as an interface so the screen can be widget-tested without
/// touching `file_picker`, `share_plus` or the system clipboard.
abstract interface class ProfileShareService {
  /// Opens a save dialog with [suggestedName] and writes [content]; returns
  /// the saved filename for display, or `null` if the user cancels. Throws
  /// on I/O failure.
  Future<String?> saveProfile({
    required String suggestedName,
    required String content,
  });

  /// Opens the OS share sheet with [content] and an optional [subject].
  Future<void> shareProfile({
    required String content,
    required Rect sharePositionOrigin,
    String? subject,
  });

  /// Copies [content] to the system clipboard.
  Future<void> copyProfile(String content);
}

/// Production [ProfileShareService] over `file_picker`, `share_plus` and
/// Flutter's clipboard channel.
class DefaultProfileShareService implements ProfileShareService {
  /// Creates the default service.
  const DefaultProfileShareService();

  @override
  Future<String?> saveProfile({
    required String suggestedName,
    required String content,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final saved = await FilePicker.saveFile(
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: const ['conf'],
      bytes: bytes,
    );
    if (saved != null && (Platform.isMacOS || Platform.isLinux)) {
      await hardenExportedProfile(saved.toFilePath());
    }
    return saved == null ? null : suggestedName;
  }

  @override
  Future<void> shareProfile({
    required String content,
    required Rect sharePositionOrigin,
    String? subject,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        text: content,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  @override
  Future<void> copyProfile(String content) {
    return Clipboard.setData(ClipboardData(text: content));
  }
}

/// Provides the [ProfileShareService] for the profile screen.
final Provider<ProfileShareService> profileShareServiceProvider =
    Provider<ProfileShareService>((ref) => const DefaultProfileShareService());
