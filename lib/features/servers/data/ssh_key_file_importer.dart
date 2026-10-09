import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Imports an SSH public key from a file the user picks, returning its UTF-8
/// content (or `null` when the user cancels). Throws when the file cannot be
/// read or is not valid UTF-8.
///
/// A function seam — overridden in widget tests with a fake, since launching
/// the OS file picker is not possible in a pure widget test harness.
typedef SshKeyFileImporter = Future<String?> Function();

/// Default [SshKeyFileImporter] backed by the `file_picker` plugin.
///
/// `.pub` is conventional, but the picker stays permissive (any file) so
/// `.txt` and unsuffixed exports work too — the content is validated after.
Future<String?> filePickerImportPublicKey() async {
  // file_picker 12.x returns the picked files directly (empty when cancelled),
  // not a nullable FilePickerResult with a `.files` list.
  final files = await FilePicker.pickFiles();
  if (files.isEmpty) {
    return null;
  }
  final bytes = await files.single.readAsBytes();
  return utf8.decode(bytes);
}

/// Provides the [SshKeyFileImporter] used by the add-key dialog.
final Provider<SshKeyFileImporter> sshKeyFileImporterProvider =
    Provider<SshKeyFileImporter>((ref) => filePickerImportPublicKey);
