import 'package:meta/meta.dart';

/// Repo on GitHub. Single source of truth for the issue URL host.
const String _issueRepo = 'Kasbrut/fav';

/// Free-text fields collected from `ReportIssueScreen`.
@immutable
class ReportIssueFields {
  /// Creates a fields snapshot.
  const ReportIssueFields({
    required this.whatYouWereDoing,
    required this.whatYouExpected,
    required this.whatHappened,
    required this.errorCode,
  });

  /// Trimmed user-entered text — "What were you doing?".
  final String whatYouWereDoing;

  /// Trimmed user-entered text — "What did you expect?".
  final String whatYouExpected;

  /// Trimmed user-entered text — "What happened instead?".
  final String whatHappened;

  /// Optional ERR-xx code id, or `null` if the user did not pick one.
  final String? errorCode;
}

/// Sanitized diagnostic snapshot (no secrets) for the issue body.
@immutable
class IssueDiagnostic {
  /// Creates a diagnostic snapshot.
  const IssueDiagnostic({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.locale,
    required this.recentErrorCodes,
  });

  /// `<version>+<build>` from `package_info_plus`.
  final String appVersion;

  /// `Platform.operatingSystem` (e.g. `iOS`, `Android`).
  final String platform;

  /// OS version string from `device_info_plus`.
  final String osVersion;

  /// Active app locale (e.g. `it_IT`).
  final String locale;

  /// Up to 3 most recent `ErrorCode.id` values seen by the user. May be empty.
  final List<String> recentErrorCodes;
}

/// Output of [IssueUrlBuilder.build]: the prefilled GitHub URL plus a
/// plaintext copy of the body, used as fallback when the browser cannot be
/// opened.
@immutable
class IssueUrl {
  /// Creates an [IssueUrl] result.
  const IssueUrl({required this.url, required this.plaintextBody});

  /// `https://github.com/Kasbrut/fav/issues/new?...`.
  final Uri url;

  /// Complete body for the fallback dialog; the URL may contain less text.
  final String plaintextBody;
}

/// Builds the prefilled GitHub issue URL from sanitized inputs. Pure logic,
/// no I/O.
class IssueUrlBuilder {
  /// Maximum length per free-text field before URL encoding.
  static const int maxFieldLength = 1500;

  /// Composes the GitHub issue URL from [fields] and [diagnostic].
  ///
  /// When [extendedDiagnostic] is provided and the resulting body stays under
  /// [_bodyCap], it is appended under `### Extended diagnostic`. When it would
  /// push the body over the cap, a `[diagnostic truncated]` marker is inserted
  /// instead. The three free-text fields are never re-truncated.
  static IssueUrl build({
    required ReportIssueFields fields,
    required IssueDiagnostic diagnostic,
    String? extendedDiagnostic,
  }) {
    final doing = _cap(fields.whatYouWereDoing);
    final expected = _cap(fields.whatYouExpected);
    final happened = _cap(fields.whatHappened);
    final code = fields.errorCode;

    final title = _composeTitle(happened: happened, code: code);
    final body = _composeBody(
      doing: doing,
      expected: expected,
      happened: happened,
      code: code,
      diagnostic: diagnostic,
      extendedDiagnostic: extendedDiagnostic,
    );

    Uri composeUrl(String text) => Uri.https(
      'github.com',
      '/$_issueRepo/issues/new',
      {
        'template': 'user-report.md',
        'title': title,
        'body': text,
      },
    );
    var url = composeUrl(body);
    if (url.toString().length > _urlCap) {
      // Percent encoding expands non-ASCII text by up to 12 bytes per rune.
      // Bound the actual URL and never split a UTF-16 surrogate pair.
      const suffix = '\n\n[Report truncated for URL length]';
      final runes = body.runes.toList();
      var low = 0;
      var high = runes.length;
      while (low < high) {
        final mid = (low + high + 1) ~/ 2;
        if (composeUrl(
              String.fromCharCodes(runes.take(mid)) + suffix,
            ).toString().length <=
            _urlCap) {
          low = mid;
        } else {
          high = mid - 1;
        }
      }
      url = composeUrl(String.fromCharCodes(runes.take(low)) + suffix);
    }

    return IssueUrl(url: url, plaintextBody: body);
  }

  static String _cap(String s) {
    final trimmed = s.trim();
    return trimmed.length <= maxFieldLength
        ? trimmed
        : trimmed.substring(0, maxFieldLength);
  }

  static String _composeTitle({
    required String happened,
    required String? code,
  }) {
    if (happened.isEmpty && code != null) {
      return '[user report] $code';
    }
    if (happened.isEmpty) {
      return '[user report]';
    }
    const titleCap = 60;
    final firstLine = happened.split('\n').first;
    return firstLine.length <= titleCap
        ? firstLine
        : firstLine.substring(0, titleCap);
  }

  static String _composeBody({
    required String doing,
    required String expected,
    required String happened,
    required String? code,
    required IssueDiagnostic diagnostic,
    required String? extendedDiagnostic,
  }) {
    final recent = diagnostic.recentErrorCodes.isEmpty
        ? 'none'
        : diagnostic.recentErrorCodes.join(', ');
    final core = [
      '### What I was doing',
      if (doing.isEmpty) '(not provided)' else doing,
      '',
      '### What I expected',
      if (expected.isEmpty) '(not provided)' else expected,
      '',
      '### What happened instead',
      if (happened.isEmpty) '(not provided)' else happened,
      '',
      '### Error code',
      code ?? 'not reported',
      '',
      '---',
      '### Diagnostic data (auto-attached, no secrets)',
      '- App: ${diagnostic.appVersion}',
      '- Platform: ${diagnostic.platform} ${diagnostic.osVersion}',
      '- Locale: ${diagnostic.locale}',
      '- Recent error codes: $recent',
    ].join('\n');

    if (extendedDiagnostic == null) return core;

    final withExtended =
        '$core\n\n### Extended diagnostic\n$extendedDiagnostic';
    if (withExtended.length <= _bodyCap) return withExtended;

    return '$core\n\n### Extended diagnostic\n[diagnostic truncated]';
  }

  /// Practical body length cap; leaves headroom under GitHub's ~8 KB URL limit.
  static const int _bodyCap = 7800;
  static const int _urlCap = 7800;
}
