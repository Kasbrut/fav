import 'package:fav/core/router/app_router.dart';
import 'package:fav/core/theme/app_dimens.dart';
import 'package:fav/features/profile/presentation/widgets/instruction_step_card.dart';
import 'package:fav/features/profile/presentation/widgets/instruction_store_links.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Step-by-step instructions for importing the generated client profile into
/// the official WireGuard app.
///
/// The destination platform is selected explicitly because it need not match
/// the device on which FAV is running.
class ImportInstructionsScreen extends StatefulWidget {
  /// Creates an [ImportInstructionsScreen] for the server [serverId]. The id
  /// is only used to keep the back button consistent if the back stack has
  /// been cleared.
  const ImportInstructionsScreen({required this.serverId, super.key});

  /// Identifier of the server whose profile triggered this screen.
  final String serverId;

  @override
  State<ImportInstructionsScreen> createState() =>
      _ImportInstructionsScreenState();
}

class _ImportInstructionsScreenState extends State<ImportInstructionsScreen> {
  late _ClientPlatform _platform;

  @override
  void initState() {
    super.initState();
    _platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => _ClientPlatform.android,
      TargetPlatform.iOS => _ClientPlatform.ios,
      TargetPlatform.macOS => _ClientPlatform.macos,
      TargetPlatform.windows => _ClientPlatform.windows,
      TargetPlatform.linux => _ClientPlatform.linux,
      TargetPlatform.fuchsia => _ClientPlatform.android,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        // Mirror ProfileResultScreen: pop when possible, fall back to the
        // profile screen so the user always has a visible way out.
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(profileResultPath(widget.serverId));
            }
          },
        ),
        title: Text(l10n.instructionsTitle),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: DropdownButtonFormField<_ClientPlatform>(
              key: const Key('client-platform-selector'),
              initialValue: _platform,
              decoration: InputDecoration(
                labelText: l10n.instructionsClientPlatformLabel,
                helperText: l10n.instructionsClientPlatformHint,
              ),
              items: [
                for (final platform in _ClientPlatform.values)
                  DropdownMenuItem(
                    value: platform,
                    child: Text(platform.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _platform = value);
              },
            ),
          ),
          Expanded(child: _StepList(steps: _stepsFor(_platform, l10n))),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('declare-profile-imported'),
                onPressed: () => context.pop(true),
                icon: const Icon(Icons.person_outline),
                label: Text(l10n.instructionsDeclareImported),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Supported destinations for the minimal client instructions.
enum _ClientPlatform { android, ios, macos, windows, linux }

extension on _ClientPlatform {
  String get label => switch (this) {
    _ClientPlatform.android => 'Android',
    _ClientPlatform.ios => 'iOS / iPadOS',
    _ClientPlatform.macos => 'macOS',
    _ClientPlatform.windows => 'Windows',
    _ClientPlatform.linux => 'Linux',
  };
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});

  final List<_InstructionStep> steps;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: steps.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final step = steps[index];
        return InstructionStepCard(
          number: step.number,
          title: step.title,
          description: step.description,
          screenshotAsset: step.screenshotAsset,
          storeLinks: step.storeLinks,
        );
      },
    );
  }
}

/// Lightweight value object for an instruction step.
///
/// Kept private — instruction content is static UI and does not need to leak
/// outside this screen. The visual screenshot slot lives on
/// [InstructionStepCard.screenshotAsset]; when artwork is shipped, pass it
/// inline in the builder below. The "install" steps instead carry [storeLinks]
/// and render store buttons rather than a screenshot.
class _InstructionStep {
  const _InstructionStep({
    required this.number,
    required this.title,
    required this.description,
    this.screenshotAsset,
    this.storeLinks = const [],
  });

  final int number;
  final String title;
  final String description;
  final String? screenshotAsset;
  final List<WireguardStore> storeLinks;
}

List<_InstructionStep> _androidSteps(AppLocalizations l10n) => [
  _InstructionStep(
    number: 1,
    title: l10n.instructionsAndroidStep1Title,
    description: l10n.instructionsAndroidStep1Body,
    storeLinks: const [WireguardStore.playStore],
  ),
  _InstructionStep(
    number: 2,
    title: l10n.instructionsAndroidStep2Title,
    description: l10n.instructionsAndroidStep2Body,
  ),
  _InstructionStep(
    number: 3,
    title: l10n.instructionsAndroidStep3Title,
    description: l10n.instructionsAndroidStep3Body,
  ),
  _InstructionStep(
    number: 4,
    title: l10n.instructionsAndroidStep4Title,
    description: l10n.instructionsAndroidStep4Body,
    screenshotAsset: 'lib/assets/help/import/wireguard-android-import.webp',
  ),
  _InstructionStep(
    number: 5,
    title: l10n.instructionsAndroidStep5Title,
    description: l10n.instructionsAndroidStep5Body,
  ),
  _InstructionStep(
    number: 6,
    title: l10n.instructionsAndroidStep6Title,
    description: l10n.instructionsAndroidStep6Body,
  ),
  _InstructionStep(
    number: 7,
    title: l10n.instructionsAndroidProtectionTitle,
    description: l10n.instructionsAndroidProtectionBody,
  ),
];

List<_InstructionStep> _iosSteps(AppLocalizations l10n) => [
  _InstructionStep(
    number: 1,
    title: l10n.instructionsIosStep1Title,
    description: l10n.instructionsIosStep1Body,
    storeLinks: const [WireguardStore.appStore],
  ),
  _InstructionStep(
    number: 2,
    title: l10n.instructionsIosStep2Title,
    description: l10n.instructionsIosStep2Body,
  ),
  _InstructionStep(
    number: 3,
    title: l10n.instructionsIosStep3Title,
    description: l10n.instructionsIosStep3Body,
    screenshotAsset: 'lib/assets/help/import/wireguard-ios-import.webp',
  ),
  _InstructionStep(
    number: 4,
    title: l10n.instructionsIosStep4Title,
    description: l10n.instructionsIosStep4Body,
  ),
  _InstructionStep(
    number: 5,
    title: l10n.instructionsIosStep5Title,
    description: l10n.instructionsIosStep5Body,
  ),
  _InstructionStep(
    number: 6,
    title: l10n.instructionsExternalMeasureTitle,
    description: l10n.instructionsExternalMeasureBody('iOS / iPadOS'),
  ),
];

List<_InstructionStep> _desktopSteps(
  AppLocalizations l10n,
  _ClientPlatform platform,
) => [
  _InstructionStep(
    number: 1,
    title: l10n.instructionsDesktopStep1Title(platform.label),
    description: l10n.instructionsDesktopStep1Body,
  ),
  _InstructionStep(
    number: 2,
    title: l10n.instructionsDesktopStep2Title,
    description: l10n.instructionsDesktopStep2Body,
  ),
  _InstructionStep(
    number: 3,
    title: l10n.instructionsExternalMeasureTitle,
    description: l10n.instructionsExternalMeasureBody(platform.label),
  ),
];

List<_InstructionStep> _stepsFor(
  _ClientPlatform platform,
  AppLocalizations l10n,
) => switch (platform) {
  _ClientPlatform.android => _androidSteps(l10n),
  _ClientPlatform.ios => _iosSteps(l10n),
  _ClientPlatform.macos ||
  _ClientPlatform.windows ||
  _ClientPlatform.linux => _desktopSteps(l10n, platform),
};
