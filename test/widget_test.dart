import 'package:fav/app.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/settings/application/preferences_controller.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_preferences_repository.dart';
import 'support/server_fakes.dart';

/// Foundation smoke test: the app boots and renders the server list.
void main() {
  testWidgets('boots and shows the server list empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverRepositoryProvider.overrideWithValue(FakeServerRepository()),
          preferencesRepositoryProvider.overrideWithValue(
            FakePreferencesRepository(),
          ),
        ],
        child: const WireguardProvisionerApp(),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.serverListTitle), findsOneWidget);
    expect(find.text(l10n.serverListEmptyTitle), findsOneWidget);
  });
}
