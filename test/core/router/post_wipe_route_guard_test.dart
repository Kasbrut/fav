import 'package:fav/app.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/settings/application/app_reset_service.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/features/settings/presentation/post_wipe_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_preferences_repository.dart';
import '../../support/server_fakes.dart';

/// [AppResetService] fake: records whether `wipe()` ran.
class _FakeResetService extends AppResetService {
  _FakeResetService() : super(deleteAllSecureEntries: _noop);
  bool wiped = false;
  @override
  Future<void> wipe() async => wiped = true;
}

Future<void> _noop() async {}

void main() {
  testWidgets(
    'a platform-supplied /post-wipe route must not destroy data (H1)',
    (tester) async {
      // On Android any installed app can start MainActivity with an intent
      // extra `route=/post-wipe`; go_router prefers the platform route over
      // initialLocation. Since the wipe moved into PostWipeScreen (M11),
      // reaching the route unconfirmed IS the destruction — the router must
      // refuse it.
      tester.platformDispatcher.defaultRouteNameTestValue = '/post-wipe';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final service = _FakeResetService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            serverRepositoryProvider.overrideWithValue(FakeServerRepository()),
            preferencesRepositoryProvider.overrideWithValue(
              FakePreferencesRepository(),
            ),
            appResetServiceProvider.overrideWithValue(service),
          ],
          child: const WireguardProvisionerApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(service.wiped, isFalse);
      expect(find.byType(PostWipeScreen), findsNothing);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.serverListTitle), findsOneWidget);
    },
  );
}
