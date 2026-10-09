import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bottom-navigation shell hosting the top-level tab branches.
///
/// Wraps the Servers, Settings and Help branches of a
/// [StatefulShellRoute.indexedStack] and renders the persistent
/// [NavigationBar]; full-screen routes (add server, install, detail) are
/// pushed above this shell and therefore have no bottom navigation.
class HomeShell extends StatelessWidget {
  /// Creates a [HomeShell] driven by [navigationShell].
  const HomeShell({required this.navigationShell, super.key});

  /// The stateful shell controlling the indexed-stack branches.
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 720;
        final body = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: navigationShell,
          ),
        );
        if (expanded) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: navigationShell.currentIndex,
                    onDestinationSelected: navigationShell.goBranch,
                    labelType: NavigationRailLabelType.all,
                    leading: const SizedBox(height: AppSpacing.md),
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.dns_outlined),
                        selectedIcon: const Icon(Icons.dns),
                        label: Text(l10n.navServers),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings),
                        label: Text(l10n.navSettings),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.help_outline),
                        selectedIcon: const Icon(Icons.help),
                        label: Text(l10n.navHelp),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: navigationShell.goBranch,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.dns_outlined),
                selectedIcon: const Icon(Icons.dns),
                label: l10n.navServers,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: l10n.navSettings,
              ),
              NavigationDestination(
                icon: const Icon(Icons.help_outline),
                selectedIcon: const Icon(Icons.help),
                label: l10n.navHelp,
              ),
            ],
          ),
        );
      },
    );
  }
}
