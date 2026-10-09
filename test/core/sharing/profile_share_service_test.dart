import 'dart:io';

import 'package:fav/core/sharing/profile_share_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exported profiles are owner-only on POSIX desktops', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final directory = await Directory.systemTemp.createTemp('fav-profile-');
    addTearDown(() => directory.delete(recursive: true));
    final profile = File('${directory.path}/client.conf');
    await profile.writeAsString('[Interface]\nPrivateKey = secret\n');

    await hardenExportedProfile(profile.path);

    final permissions = profile.statSync().mode & 0x1FF;
    expect(permissions, 0x180); // 0600
  });
}
