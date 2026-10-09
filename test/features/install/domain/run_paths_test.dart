import 'package:fav/features/install/domain/run_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const paths = RunPaths('run-xyz');

  test('state files remain keyed by run id (shared with installs)', () {
    expect(paths.statePath, '/var/lib/wg-installer/run-xyz.state');
    expect(paths.exitPath, '/var/lib/wg-installer/run-xyz.exit');
  });
}
