import 'dart:convert';

import 'package:fav/features/install/data/provisioner/run_state_parser.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/domain/install_step.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = RunStateParser();

  String stateJson({
    Map<String, Map<String, String>> steps = const {},
    Object? error,
    List<String> warnings = const [],
  }) {
    return jsonEncode({
      'run_id': 'run-1',
      'started_at': '2026-05-18T10:30:00Z',
      'current_step': 'install_pkgs',
      'current_step_started_at': '2026-05-18T10:30:12Z',
      'steps': steps,
      'warnings': warnings,
      'error': error,
    });
  }

  group('RunStateParser.tryParse', () {
    test('parses a well-formed state file', () {
      final parsed = parser.tryParse(
        stateJson(
          steps: {
            'probe': {
              'status': 'done',
              'started_at': '2026-05-18T10:30:00Z',
              'ended_at': '2026-05-18T10:30:05Z',
            },
            'install_pkgs': {
              'status': 'running',
              'started_at': '2026-05-18T10:30:12Z',
            },
          },
        ),
      );
      expect(parsed, isNotNull);
      expect(parsed!.runId, 'run-1');
      expect(parsed.steps, hasLength(kRunStepKeys.length));
      expect(parsed.steps.first.key, 'probe');
      expect(parsed.steps.first.status, StepStatus.done);
      expect(parsed.steps[1].status, StepStatus.running);
      expect(parsed.steps[2].status, StepStatus.pending);
      expect(parsed.status, RunStatus.running);
    });

    test('returns null for empty or blank input', () {
      expect(parser.tryParse(''), isNull);
      expect(parser.tryParse('   '), isNull);
    });

    test('returns null for malformed JSON', () {
      expect(parser.tryParse('{not json'), isNull);
    });

    test('returns null for a truncated object', () {
      final full = stateJson();
      expect(parser.tryParse(full.substring(0, full.length ~/ 2)), isNull);
    });

    test('marks the run failed when the error field is set', () {
      final parsed = parser.tryParse(
        stateJson(
          error: 'step probe failed (exit 1)',
          steps: {
            'probe': {'status': 'error'},
          },
        ),
      );
      expect(parsed!.status, RunStatus.failed);
      expect(parsed.errorMessage, 'step probe failed (exit 1)');
    });

    test('marks the run failed when any step errored', () {
      final parsed = parser.tryParse(
        stateJson(
          steps: {
            'probe': {'status': 'error'},
          },
        ),
      );
      expect(parsed!.status, RunStatus.failed);
    });

    test('reports success when every step is done or skipped', () {
      final steps = {
        for (final key in kRunStepKeys)
          key: {'status': key == 'create_user' ? 'skipped' : 'done'},
      };
      final parsed = parser.tryParse(stateJson(steps: steps));
      expect(parsed!.status, RunStatus.success);
    });

    test('collects warnings', () {
      final parsed = parser.tryParse(
        stateJson(warnings: const ['low disk space']),
      );
      expect(parsed!.warnings, const ['low disk space']);
    });

    test('treats an unknown step status as pending', () {
      final parsed = parser.tryParse(
        stateJson(
          steps: {
            'probe': {'status': 'frobnicating'},
          },
        ),
      );
      expect(parsed!.steps.first.status, StepStatus.pending);
    });
  });
}
