import 'package:fav/core/router/home_shell.dart';
import 'package:fav/features/help/presentation/donate_screen.dart';
import 'package:fav/features/help/presentation/faq_screen.dart';
import 'package:fav/features/help/presentation/firewall_guide_screen.dart';
import 'package:fav/features/help/presentation/getting_started_screen.dart';
import 'package:fav/features/help/presentation/glossary_screen.dart';
import 'package:fav/features/help/presentation/help_hub_screen.dart';
import 'package:fav/features/help/presentation/report_issue_screen.dart';
import 'package:fav/features/help/presentation/resources_screen.dart';
import 'package:fav/features/help/presentation/troubleshooting_detail_screen.dart';
import 'package:fav/features/help/presentation/troubleshooting_list_screen.dart';
import 'package:fav/features/install/presentation/advanced_form_screen.dart';
import 'package:fav/features/install/presentation/install_progress_screen.dart';
import 'package:fav/features/install/presentation/install_server_screen.dart';
import 'package:fav/features/install/presentation/script_editor_screen.dart';
import 'package:fav/features/monitoring/presentation/history/server_history_screen.dart';
import 'package:fav/features/peers/application/peer_lookup_provider.dart';
import 'package:fav/features/peers/presentation/add_peer_screen.dart';
import 'package:fav/features/peers/presentation/peer_detail_screen.dart';
import 'package:fav/features/profile/presentation/import_instructions_screen.dart';
import 'package:fav/features/profile/presentation/profile_result_screen.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/presentation/add_server_screen.dart';
import 'package:fav/features/servers/presentation/server_detail_screen.dart';
import 'package:fav/features/servers/presentation/server_list_screen.dart';
import 'package:fav/features/settings/presentation/backup_restore_screen.dart';
import 'package:fav/features/settings/presentation/language_picker_screen.dart';
import 'package:fav/features/settings/presentation/post_wipe_screen.dart';
import 'package:fav/features/settings/presentation/settings_screen.dart';
import 'package:fav/features/shell/presentation/ssh_shell_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Route path for the server list (home) tab.
const String serverListRoute = '/';

/// Route path for the settings tab.
const String settingsRoute = '/settings';

/// Route path for the help tab.
const String helpRoute = '/help';

/// Route path for the add-server screen.
const String addServerRoute = '/servers/add';

/// Route path for the advanced installation options screen.
const String advancedFormRoute = '/servers/add/advanced';

/// Route path for the installer-script editor (Settings → Danger Zone).
const String settingsScriptsRoute = '/settings/scripts';

/// Route path for the language picker (Settings → Language).
const String settingsLanguageRoute = '/settings/language';

/// Route path for encrypted backup creation and restoration.
const String settingsBackupRoute = '/settings/backup';

/// Route path pattern for the server detail screen.
const String serverDetailRoute = '/servers/:id';

/// Route path pattern for installing WireGuard on a registered server.
const String installServerRoute = '/servers/:id/install';

/// Route path pattern for the legacy client profile screen.
/// Redirects to the oldest peer's detail screen when one exists (multi-peer
/// v1.1), or back to the server detail when none exist.
const String profileResultRoute = '/servers/:id/profile';

/// Route path pattern for the import-instructions screen.
const String importInstructionsRoute = '/servers/:id/instructions';

/// Route path pattern for the per-server connection history screen.
const String serverHistoryRoute = '/servers/:id/history';

/// Route path pattern for the interactive SSH shell screen.
const String sshShellRoute = '/servers/:id/shell';

/// Route path pattern for the add-peer form (multi-peer v1.1).
const String addPeerRoute = '/servers/:id/peers/add';

/// Route path pattern for the per-peer detail screen (multi-peer v1.1).
const String peerDetailRoute = '/servers/:id/peers/:peerId';

/// Route path for the installation progress screen.
const String installProgressRoute = '/install';

/// Route path for the post-wipe screen shown after a full app reset on
/// platforms that cannot self-terminate (everything except Android).
const String postWipeRoute = '/post-wipe';

/// Builds the server detail path for the server identified by [id].
String serverDetailPath(String id) => '/servers/$id';

/// Builds the install path for the server identified by [id].
String installServerPath(String id) => '/servers/$id/install';

/// Builds the client profile path for the server identified by [id].
String profileResultPath(String id) => '/servers/$id/profile';

/// Builds the import-instructions path for the server identified by [id].
String importInstructionsPath(String id) => '/servers/$id/instructions';

/// Builds the connection-history path for the server identified by [id].
String serverHistoryPath(String id) => '/servers/$id/history';

/// Builds the SSH shell path for the server identified by [id].
String sshShellPath(String id) => '/servers/$id/shell';

/// Builds the add-peer path for the server identified by [id].
String addPeerPath(String id) => '/servers/$id/peers/add';

/// Builds the peer-detail path for the peer identified by [peerId].
String peerDetailPath(String serverId, String peerId) =>
    '/servers/$serverId/peers/$peerId';

/// Builds the troubleshooting detail path for [code].
String troubleshootingDetailPath(String code) => '/help/errors/$code';

/// Builds the glossary entry path for [slug].
String glossaryEntryPath(String slug) => '/help/glossary/$slug';

/// Root navigator key used to push full-screen routes above the shell.
///
/// Routes that must be reachable from outside the [StatefulShellRoute]
/// (e.g. deep-links triggered from [AddServerScreen]) declare
/// `parentNavigatorKey: _rootNavigatorKey` so go_router places them above
/// the shell, avoiding a duplicate [HeroControllerScope] key assertion.
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Provides the application [GoRouter].
final Provider<GoRouter> routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: serverListRoute,
    // The app declares no deep links, but on Android any installed app can
    // start MainActivity with a `route` intent extra and go_router would
    // prefer it over [initialLocation] — a doorway straight to internal
    // routes (security audit H1 on the wipe flow). Ignore platform routes.
    overridePlatformDefaultLocation: true,
    routes: [
      // Bottom-navigation shell: the Servers, Settings and Help tabs.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: serverListRoute,
                builder: (context, state) => const ServerListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: settingsRoute,
                builder: (context, state) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'scripts',
                    builder: (context, state) => const ScriptEditorScreen(),
                  ),
                  GoRoute(
                    path: 'language',
                    builder: (context, state) => const LanguagePickerScreen(),
                  ),
                  GoRoute(
                    path: 'backup',
                    builder: (context, state) => const BackupRestoreScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: helpRoute,
                builder: (context, state) => const HelpHubScreen(),
                routes: [
                  GoRoute(
                    path: 'getting-started',
                    builder: (context, state) => const GettingStartedScreen(),
                  ),
                  GoRoute(
                    path: 'glossary',
                    builder: (context, state) => const GlossaryScreen(),
                    routes: [
                      GoRoute(
                        path: ':term',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => GlossaryScreen(
                          term: state.pathParameters['term'],
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'errors',
                    builder: (context, state) =>
                        const TroubleshootingListScreen(),
                    routes: [
                      GoRoute(
                        path: ':code',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) =>
                            TroubleshootingDetailScreen(
                              code: state.pathParameters['code']!,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'firewall',
                    builder: (context, state) => const FirewallGuideScreen(),
                  ),
                  GoRoute(
                    path: 'faq',
                    builder: (context, state) => const FaqScreen(),
                  ),
                  GoRoute(
                    path: 'resources',
                    builder: (context, state) => const ResourcesScreen(),
                  ),
                  GoRoute(
                    path: 'donate',
                    builder: (context, state) => const DonateScreen(),
                  ),
                  GoRoute(
                    path: 'report-issue',
                    builder: (context, state) => const ReportIssueScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Full-screen routes pushed above the shell (no bottom navigation).
      GoRoute(
        path: addServerRoute,
        builder: (context, state) => AddServerScreen(
          retryServer: state.extra is Server ? state.extra! as Server : null,
        ),
      ),
      GoRoute(
        path: advancedFormRoute,
        builder: (context, state) => const AdvancedFormScreen(),
      ),
      GoRoute(
        path: installProgressRoute,
        builder: (context, state) => const InstallProgressScreen(),
      ),
      GoRoute(
        path: serverDetailRoute,
        builder: (context, state) =>
            ServerDetailScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: installServerRoute,
        builder: (context, state) =>
            InstallServerScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: profileResultRoute,
        // Legacy v1.0 deep link: rewrite to the oldest peer's detail screen.
        // When no peer exists yet (server installed but every peer was
        // revoked), fall back to the server detail so the "Peers" empty
        // state is visible.
        redirect: (context, state) async {
          final serverId = state.pathParameters['id']!;
          final peers = await ProviderScope.containerOf(
            context,
            listen: false,
          ).read(peersByServerProvider(serverId).future);
          if (peers.isEmpty) {
            return serverDetailPath(serverId);
          }
          return peerDetailPath(serverId, peers.first.id);
        },
        builder: (context, state) =>
            ProfileResultScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: addPeerRoute,
        builder: (context, state) =>
            AddPeerScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: peerDetailRoute,
        builder: (context, state) => PeerDetailScreen(
          serverId: state.pathParameters['id']!,
          peerId: state.pathParameters['peerId']!,
        ),
      ),
      GoRoute(
        path: importInstructionsRoute,
        builder: (context, state) =>
            ImportInstructionsScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: serverHistoryRoute,
        builder: (context, state) =>
            ServerHistoryScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: sshShellRoute,
        // No `extra` here on purpose: the login password is handed to the
        // screen through PendingShellPasswords. A route extra would be
        // JSON-encoded into the engine's route-information state on every
        // report (audit MEDIUM-2, spec §10).
        builder: (context, state) =>
            SshShellScreen(serverId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: postWipeRoute,
        // The screen performs the wipe itself (audit M11), so reaching it IS
        // the destruction: require the in-memory confirmation token that only
        // the danger zone sets after the typed-word flow. Anything else — a
        // platform-injected route, a restored location — bounces to the
        // server list untouched (security audit H1).
        redirect: (context, state) =>
            state.extra == true ? null : serverListRoute,
        builder: (context, state) => const PostWipeScreen(),
      ),
    ],
  );
});
