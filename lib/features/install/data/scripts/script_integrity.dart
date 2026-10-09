import 'package:fav/core/crypto/sha256_hasher.dart';
import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/scripts/asset_script_repository.dart';
import 'package:fav/features/install/domain/script_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Expected SHA-256 (lowercase hex) of every bundled script, keyed by path.
///
/// This is the trusted baseline compiled into the app (spec §8.6); it is kept
/// honest by `test/features/install/data/scripts/script_integrity_test.dart`,
/// which recomputes the hashes from the real asset files and fails on drift.
const Map<String, String> kBundledScriptHashes = {
  'disable_password_auth.sh':
      '14467115e858be3cf1ea74f2f7ad75dfd3ddc9491c733567b0fd7550d287b9b5',
  'disable_root_ssh.sh':
      'c86102e90473e005719bea75a55a8ec03487dcf18f502f3fc545d47b6d3385de',
  'install_monitor.sh':
      '41f3ac5824815e461de4dcf2136f551186cd7c924312fc8342090071bec47278',
  'install_wireguard.sh':
      '7632ba46911534c0e340cd51f4dc0897c15739700f8904f30a449c1d0b265274',
  'lib/common.sh':
      '26b76bf5ff7d7e5f521d27786aae2c6dc22e04587bd336fa9ff57f7e7a098b18',
  'lib/firewall_manager.py':
      '7c04d21981247278871274a76970dea787c04ae5aa730ea6b60eeee4bdc12f01',
  'lib/network_probe.py':
      '932035d61703839b3625c6da3127b659a8fd886b48eff9d246b87800f9ba7fc7',
  'lib/profile_renderer.py':
      'c64d9e5c5087321da9dd7055806a84302ce5fc33b6b0df692f33ea9932bd46db',
  'lib/wg-monitor.logrotate':
      '93a5c0c56be034dd6a96dffeaa4214eb13d131885b6557f33ffd9b47cda23dc0',
  'lib/wg-monitor.service':
      'e85891a8203352e5ba04821df3425daee1f5ec9b6f6b4f9e7140509971051f36',
  'lib/wg-monitor.timer':
      '3dea2558b20fdfb2e1c5783dbc005b4215fe3b9a362504d73a26563b8d14c9c7',
  'modules/00_probe.sh':
      'adf3b83e23750a1e322b48d5775f78ef39c2937d69bbe3ac1c743341ae509708',
  'modules/10_install_pkgs.sh':
      '85419bb0510c1a2145b6aa3868defb2a9561e74c0b651f05d516f1140e20484b',
  'modules/15_network_probe.sh':
      '464f56613314c2da2d8024eef9a8dbd0cf828bbc08d126df497d58c66300431e',
  'modules/20_create_user.sh':
      'ba6cb352280e7d64c67b10682d167615b0805ad51b558aad76ad0a7f815860fb',
  'modules/25_deploy_app_key.sh':
      '2c88dc1a6da314a46aaf23684dc7d7659e631104065ec8bc7f162d90cac60c21',
  'modules/26_deploy_user_keys.sh':
      '76acd01e431db9feb065553d9851b29bdd29b4dd03da43e00103bd6cc0675f11',
  'modules/30_generate_keys.sh':
      'f3d0d0cf0c5bdaa406f28ef44dba7fe2a99df60e6eb92e2a30d46ade8a5256fc',
  'modules/40_write_server_conf.sh':
      'e57aaaec4fa597e57ca77ea1126c8b1cc4d261d5c57d66323630bc5acba8337f',
  'modules/45_firewall_guard.sh':
      'c1dd43b08a9920bc08b32ba2686aa0bc2fd0ac1e622dbb4be4c1ccd4235c30dc',
  'modules/50_enable_forwarding.sh':
      '3ef93ec93562f250aa04e228ce73e27e5f949f5585d0065094438410ab162d8f',
  'modules/60_firewall.sh':
      '7b65ddfcbd081229e845f2cc1af3eaff0feb1950bd204d0405a4c81f0bf6844a',
  'modules/70_start_service.sh':
      '221e2f29319d1238924f6a5e0706837a4cdb4840342256ac91932ef29d497469',
  'modules/80_hardening.sh':
      '99add06a4e2b58c06f54eaa75be24b7dc814af1404a921fb9a5709f0825ece1f',
  'modules/90_health_check.sh':
      '60946eba106f1dfc060d7b38e0da786715539cb0facbd3c7b1ae4dae44e786f6',
  'modules/99_finalize.sh':
      '3222b8d1251050dfd82326d49bd11c08249d70a4f7f106570b4748e54436ccff',
  'reopen_ssh.sh':
      '41595d0afba2b08b2e7e7af4e3dc04a8c625bdd0dc910b417e2c04df0796d194',
  'teardown/modules/10_stop_service.sh':
      'be5d14ddd7de7a027100ab6f48f6779174da59cb67af544e9e13f828f5b4a734',
  'teardown/modules/20_remove_monitor.sh':
      '6019d7b255babd934b8cda5772208570e543892642359f7e123312a859237635',
  'teardown/modules/30_remove_firewall.sh':
      '7a8c44c55b70d5c2d82a7e1c314ffea80ecd2c5df062bf0ca1939c84ed684bd9',
  'teardown/modules/40_remove_forwarding.sh':
      'd43f18fdf40015bf497d0d635abfd870c1a407cf4318ed12f0cd6bb076c2ae1c',
  'teardown/modules/50_remove_config.sh':
      'e5808f91b7ab1bf859e990eecc67bc4432b2a9ed3954a6e9d0513366f1eb43f4',
  'teardown/modules/60_remove_fail2ban_jail.sh':
      '133989cd3f9f86cfade76bfc10e355176e5e1561ccee73ae1d87722013f0a596',
  'teardown_wireguard.sh':
      '442c03a72f5cc8b3b053fc882730c0d2c7e30149c7a3cb9c4ad23afb5350fb03',
  'wg-monitor.sh':
      '84ab6040a69d996c88de64ec0d68af98fcb4af33d11bb227850e49d7bf35dff2',
};

/// Expected canonical hash over the whole bundled script set (spec §8.6).
const String kBundledScriptSetHash =
    '417cf5715ede4148034019123c080bd1192eb2aa09d77ea93247ad47815c303f';

/// Verifies the bundled scripts against the compiled-in hashes (spec §8.6).
class ScriptIntegrityVerifier {
  /// Creates a [ScriptIntegrityVerifier] reading from [_repository].
  ScriptIntegrityVerifier(this._repository);

  final AssetScriptRepository _repository;

  /// Loads the bundled scripts and verifies their integrity.
  ///
  /// Throws an [AppException] with [ErrorCode.scriptInvalid] (fail-closed) on
  /// any missing file, per-file hash mismatch, or set-hash mismatch.
  Future<ScriptBundle> verifyAndLoad() async {
    final bundle = await _repository.loadDefaultBundle();
    if (bundle.assets.length != kBundledScriptHashes.length) {
      throw const AppException(
        ErrorCode.scriptInvalid,
        detail: 'bundled script count mismatch',
      );
    }
    for (final asset in bundle.assets) {
      final expected = kBundledScriptHashes[asset.relativePath];
      if (expected == null || sha256Hex(asset.bytes) != expected) {
        throw const AppException(
          ErrorCode.scriptInvalid,
          detail: 'bundled script integrity check failed',
        );
      }
    }
    if (bundle.bundleHash != kBundledScriptSetHash) {
      throw const AppException(
        ErrorCode.scriptInvalid,
        detail: 'bundled script set integrity check failed',
      );
    }
    return bundle;
  }
}

/// Provides the [ScriptIntegrityVerifier].
final Provider<ScriptIntegrityVerifier> scriptIntegrityVerifierProvider =
    Provider<ScriptIntegrityVerifier>(
      (ref) => ScriptIntegrityVerifier(ref.watch(scriptRepositoryProvider)),
    );

/// Verifies the bundled scripts once at startup and caches the result.
///
/// An error state means the app must block provisioning with the default
/// script (spec §8.6, fail-closed).
final FutureProvider<ScriptBundle> bootIntegrityProvider =
    FutureProvider<ScriptBundle>(
      (ref) => ref.watch(scriptIntegrityVerifierProvider).verifyAndLoad(),
    );
