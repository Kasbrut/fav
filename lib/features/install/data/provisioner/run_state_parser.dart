import 'dart:convert';

import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:meta/meta.dart';

/// Canonical ordered list of installation step keys (mirrors `common.sh`).
const List<String> kRunStepKeys = [
  'probe',
  'install_pkgs',
  'create_user',
  'deploy_app_key',
  'generate_keys',
  'write_server_conf',
  'enable_forwarding',
  'firewall',
  'start_service',
  'hardening',
  'health_check',
  'finalize',
];

/// Immutable snapshot parsed from a run state file (spec §7.4).
@immutable
class ParsedRunState {
  /// Creates a [ParsedRunState].
  const ParsedRunState({
    required this.runId,
    required this.startedAt,
    required this.status,
    required this.steps,
    required this.warnings,
    this.currentStep,
    this.errorMessage,
  });

  /// Run identifier reported by the state file.
  final String runId;

  /// When the run started.
  final DateTime startedAt;

  /// Overall status derived from the steps and the error field.
  final RunStatus status;

  /// Steps in canonical installer order.
  final List<InstallStep> steps;

  /// Non-fatal warnings reported by the installer.
  final List<String> warnings;

  /// Key of the step currently running, if any.
  final String? currentStep;

  /// Run-level error message; `null` when the run has not failed.
  final String? errorMessage;
}

/// Parses the JSON run state file written by the installer (spec §7.4).
class RunStateParser {
  /// Creates a [RunStateParser].
  const RunStateParser();

  /// Parses [rawJson] into a [ParsedRunState].
  ///
  /// Returns `null` when the input is empty, truncated or otherwise malformed
  /// — the state file may be read while the installer is rewriting it.
  ParsedRunState? tryParse(String rawJson) {
    if (rawJson.trim().isEmpty) {
      return null;
    }
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      root = decoded;
    } on FormatException {
      return null;
    }

    final runId = root['run_id'];
    final startedRaw = root['started_at'];
    if (runId is! String || startedRaw is! String) {
      return null;
    }
    final startedAt = DateTime.tryParse(startedRaw);
    if (startedAt == null) {
      return null;
    }

    final stepsJson = root['steps'];
    final stepsMap = stepsJson is Map<String, dynamic>
        ? stepsJson
        : const <String, dynamic>{};
    final steps = [
      for (final key in kRunStepKeys) _parseStep(key, stepsMap[key]),
    ];

    final warnings = <String>[];
    final warningsJson = root['warnings'];
    if (warningsJson is List) {
      for (final warning in warningsJson) {
        if (warning is String) {
          warnings.add(warning);
        }
      }
    }

    final error = root['error'];
    final errorMessage = error is String && error.isNotEmpty ? error : null;
    final currentStep = root['current_step'];

    return ParsedRunState(
      runId: runId,
      startedAt: startedAt,
      status: _deriveStatus(steps, errorMessage),
      steps: steps,
      warnings: warnings,
      currentStep: currentStep is String ? currentStep : null,
      errorMessage: errorMessage,
    );
  }

  InstallStep _parseStep(String key, Object? raw) {
    if (raw is! Map<String, dynamic>) {
      return InstallStep(key: key, status: StepStatus.pending, label: key);
    }
    return InstallStep(
      key: key,
      status: _parseStepStatus(raw['status']),
      label: key,
      startedAt: _parseTime(raw['started_at']),
      completedAt: _parseTime(raw['ended_at']),
    );
  }

  StepStatus _parseStepStatus(Object? raw) {
    return switch (raw) {
      'running' => StepStatus.running,
      'done' => StepStatus.done,
      'error' => StepStatus.error,
      'skipped' => StepStatus.skipped,
      _ => StepStatus.pending,
    };
  }

  DateTime? _parseTime(Object? raw) {
    return raw is String ? DateTime.tryParse(raw) : null;
  }

  RunStatus _deriveStatus(List<InstallStep> steps, String? errorMessage) {
    if (errorMessage != null ||
        steps.any((step) => step.status == StepStatus.error)) {
      return RunStatus.failed;
    }
    final allSettled = steps.every(
      (step) =>
          step.status == StepStatus.done || step.status == StepStatus.skipped,
    );
    return allSettled ? RunStatus.success : RunStatus.running;
  }
}
