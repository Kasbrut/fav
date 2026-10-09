import 'package:meta/meta.dart';

/// Lifecycle status of a single installation step (spec §7.4).
enum StepStatus {
  /// The step has not started yet.
  pending,

  /// The step is currently running.
  running,

  /// The step completed successfully.
  done,

  /// The step failed.
  error,

  /// The step was skipped (not applicable to this run).
  skipped,
}

/// A single step of an installation run.
@immutable
class InstallStep {
  /// Creates an [InstallStep].
  const InstallStep({
    required this.key,
    required this.status,
    required this.label,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
  });

  /// Stable step identifier (for example `probe`, `install_pkgs`).
  final String key;

  /// Current status of the step.
  final StepStatus status;

  /// User-visible label for the step.
  final String label;

  /// When the step started; `null` while pending.
  final DateTime? startedAt;

  /// When the step finished; `null` until done or failed.
  final DateTime? completedAt;

  /// Failure description when [status] is [StepStatus.error]; `null` otherwise.
  final String? errorMessage;

  /// Returns a copy of this step with the given fields replaced.
  InstallStep copyWith({
    String? key,
    StepStatus? status,
    String? label,
    DateTime? startedAt,
    DateTime? completedAt,
    String? errorMessage,
  }) {
    return InstallStep(
      key: key ?? this.key,
      status: status ?? this.status,
      label: label ?? this.label,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is InstallStep &&
        other.key == key &&
        other.status == status &&
        other.label == label &&
        other.startedAt == startedAt &&
        other.completedAt == completedAt &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode {
    return Object.hash(
      key,
      status,
      label,
      startedAt,
      completedAt,
      errorMessage,
    );
  }
}
