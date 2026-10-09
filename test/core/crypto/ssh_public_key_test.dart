// Real SSH public keys are single unsplittable base64 tokens that must stay
// verbatim; let the fixtures overflow the line limit.
// ignore_for_file: lines_longer_than_80_chars

import 'package:fav/core/crypto/ssh_public_key.dart';
import 'package:flutter_test/flutter_test.dart';

// Real keys generated with `ssh-keygen`; the ed25519 fingerprint below is the
// `ssh-keygen -lf` output for that key.
const _ed25519 =
    'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILumuaB4RSmE61UE6zVVVutcGA5HoayYq1PhFhdkFg9e user@laptop';
const _ed25519Fingerprint =
    'SHA256:60LKL82Fi5QVhVaE7DYVwGLRjiwHzCvi8RupJ+rqD3I';
const _rsa =
    'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCxIH2ukPCOYGE8nzrdUlF4SRGB8plpMa8iJJ9yuZnC1Sg5DTxTCfRNpa7uxcs+R4i6c46c8S2QVnEI+CEGQH0mjK8+miKBPpIEFaim937TiB0p9PXwEz+IdiYAv5Ev8pkN/C1ePpRiArlS4vgZByAfCdl2tk9h/BQd8RXbVaQvmTCCNkKqVSmM0kIT95+Hwo6k0KwXJBXuOZ4els7DxkXqgvsJixefbvvgQ+/KR4671hTYZzY7CUi+riJ43jWcFSYjbD2KP/ygNea/GwY9TSFU5fgqiEKDSJWnrThPFMsJ/fgkImdc8DVTKsLXIYIXzZuSmGICFuFF82hoxXhh09iX user@laptop';
const _ecdsa256 =
    'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNmgyuhxJ9EPQLBJmjtoEUPFZmgXvDc3sbBFo7OJMaCndzAiCfcCHXzVqOpZhzkVS3r4q6Gbhjbz0MFBhNPOkJo=';
const _ecdsa521 =
    'ecdsa-sha2-nistp521 AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBACpxZDnvky4QQ2CkQP1kJOlegQAjWpRbERUgKhHZmDQwgVhndyfUXi/+Zpmq8Zgr+NnPL8R7PfI+FIYgKQg7xifcABrWyRs6Ou1sG40lCPjaS6rYB8G/sSxUiaa12U2KlM0cqPubOrJ4XQW7mYRzuGfrdHiLAD8R5Myvt76hVuQhvAxEQ== me@host';

void main() {
  group('SshPublicKey.tryParse', () {
    test('parses an ed25519 key with type, comment and fingerprint', () {
      final key = SshPublicKey.tryParse(_ed25519);
      expect(key, isNotNull);
      expect(key!.algorithm, 'ssh-ed25519');
      expect(key.comment, 'user@laptop');
      expect(key.fingerprint, _ed25519Fingerprint);
      expect(key.line, _ed25519);
    });

    test('accepts rsa, ecdsa-256 and ecdsa-521 keys', () {
      expect(SshPublicKey.tryParse(_rsa)?.algorithm, 'ssh-rsa');
      expect(
        SshPublicKey.tryParse(_ecdsa256)?.algorithm,
        'ecdsa-sha2-nistp256',
      );
      expect(
        SshPublicKey.tryParse(_ecdsa521)?.algorithm,
        'ecdsa-sha2-nistp521',
      );
    });

    test('parses a key with no comment', () {
      // The ecdsa-256 fixture was generated with an empty comment.
      final key = SshPublicKey.tryParse(_ecdsa256.trimRight());
      expect(key, isNotNull);
      expect(key!.comment, '');
      expect(key.line, isNot(endsWith(' ')));
    });

    test('normalizes surrounding and internal whitespace', () {
      final key = SshPublicKey.tryParse('  $_ed25519  ');
      expect(key, isNotNull);
      expect(key!.line, _ed25519);
    });

    test('preserves a multi-word comment', () {
      final raw = '${_ed25519.split(' ').take(2).join(' ')} my home laptop';
      final key = SshPublicKey.tryParse(raw);
      expect(key?.comment, 'my home laptop');
    });

    test('rejects an unknown key type', () {
      expect(
        SshPublicKey.tryParse('ssh-dss AAAAB3NzaC1kc3M= user@host'),
        isNull,
      );
    });

    test('rejects a type/blob algorithm mismatch', () {
      // Claim ssh-rsa but provide an ed25519 blob.
      final blob = _ed25519.split(' ')[1];
      expect(SshPublicKey.tryParse('ssh-rsa $blob comment'), isNull);
    });

    test('rejects non-base64 blob', () {
      expect(SshPublicKey.tryParse('ssh-ed25519 not!base64 c'), isNull);
    });

    test('rejects empty and blank input', () {
      expect(SshPublicKey.tryParse(''), isNull);
      expect(SshPublicKey.tryParse('   '), isNull);
    });

    test('rejects a missing blob', () {
      expect(SshPublicKey.tryParse('ssh-ed25519'), isNull);
    });

    test('rejects control characters and embedded newlines', () {
      expect(SshPublicKey.tryParse('$_ed25519\n$_rsa'), isNull);
      expect(SshPublicKey.tryParse('ssh-ed25519\tAAAA c'), isNull);
    });

    test('equality is based on the normalized line', () {
      expect(
        SshPublicKey.tryParse('  $_ed25519  '),
        SshPublicKey.tryParse(_ed25519),
      );
    });
  });
}
