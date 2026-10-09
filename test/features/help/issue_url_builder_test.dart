import 'package:fav/features/help/data/issue_url_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bounds the encoded URL for non-ASCII reports without losing the fallback',
    () {
      final result = IssueUrlBuilder.build(
        fields: ReportIssueFields(
          whatYouWereDoing: '你' * 1500,
          whatYouExpected: '😀' * 700,
          whatHappened: 'é' * 1500,
          errorCode: null,
        ),
        diagnostic: const IssueDiagnostic(
          appVersion: '1.0',
          platform: 'iOS',
          osVersion: '17',
          locale: 'zh',
          recentErrorCodes: [],
        ),
      );
      expect(result.url.toString().length, lessThanOrEqualTo(7800));
      expect(result.url.queryParameters['body'], contains('[Report truncated'));
      expect(result.url.queryParameters['body'], isNot(contains('�')));
      expect(result.plaintextBody, contains('你' * 1500));
      expect(result.plaintextBody, contains('😀' * 700));
    },
  );

  const diagnostic = IssueDiagnostic(
    appVersion: '1.2.0+34',
    platform: 'iOS',
    osVersion: '17.4',
    locale: 'it_IT',
    recentErrorCodes: ['ERR-CONN-01', 'ERR-AUTH-02'],
  );

  test('builds a GitHub issue URL with sanitized body', () {
    const fields = ReportIssueFields(
      whatYouWereDoing: 'Adding a peer',
      whatYouExpected: 'A QR code',
      whatHappened: 'A red error',
      errorCode: null,
    );

    final result = IssueUrlBuilder.build(
      fields: fields,
      diagnostic: diagnostic,
    );

    expect(
      result.url.toString(),
      startsWith(
        'https://github.com/Kasbrut/fav/issues/new',
      ),
    );
    expect(result.url.queryParameters['template'], 'user-report.md');
    expect(result.url.queryParameters['title'], isNotEmpty);
    expect(result.url.queryParameters['body'], contains('Adding a peer'));
    expect(result.url.queryParameters['body'], contains('A QR code'));
    expect(result.url.queryParameters['body'], contains('A red error'));
    expect(result.url.queryParameters['body'], contains('1.2.0+34'));
    expect(result.url.queryParameters['body'], contains('iOS'));
    expect(result.url.queryParameters['body'], contains('17.4'));
    expect(result.url.queryParameters['body'], contains('it_IT'));
    expect(
      result.url.queryParameters['body'],
      contains('ERR-CONN-01, ERR-AUTH-02'),
    );
    expect(result.url.queryParameters['body'], contains('Error code'));
    expect(result.plaintextBody, equals(result.url.queryParameters['body']));
  });

  test('caps free-text fields to 1500 chars each', () {
    final long = 'x' * 5000;
    final result = IssueUrlBuilder.build(
      fields: ReportIssueFields(
        whatYouWereDoing: long,
        whatYouExpected: 'short',
        whatHappened: 'short',
        errorCode: null,
      ),
      diagnostic: diagnostic,
    );
    final capped = result.plaintextBody.split('### What I was doing').last;
    expect(capped.contains('x' * 1501), isFalse);
  });

  test(
    'title falls back to "[user report] <code>" when free text is empty',
    () {
      final result = IssueUrlBuilder.build(
        fields: const ReportIssueFields(
          whatYouWereDoing: '',
          whatYouExpected: '',
          whatHappened: '',
          errorCode: 'ERR-CONN-02',
        ),
        diagnostic: diagnostic,
      );
      expect(result.url.queryParameters['title'], '[user report] ERR-CONN-02');
    },
  );

  test('body marks error code as "not reported" when null', () {
    final result = IssueUrlBuilder.build(
      fields: const ReportIssueFields(
        whatYouWereDoing: 'something',
        whatYouExpected: 'something',
        whatHappened: 'something',
        errorCode: null,
      ),
      diagnostic: diagnostic,
    );
    expect(result.plaintextBody, contains('Error code\nnot reported'));
  });

  group('extended diagnostic', () {
    test('appends section when present and under cap', () {
      const fields = ReportIssueFields(
        whatYouWereDoing: 'doing',
        whatYouExpected: 'expected',
        whatHappened: 'happened',
        errorCode: null,
      );
      final result = IssueUrlBuilder.build(
        fields: fields,
        diagnostic: diagnostic,
        extendedDiagnostic: 'EXTRA-DIAGNOSTIC-PAYLOAD',
      );
      expect(result.plaintextBody, contains('### Extended diagnostic'));
      expect(result.plaintextBody, contains('EXTRA-DIAGNOSTIC-PAYLOAD'));
    });

    test(
      'replaces the section with a truncation marker when URL would exceed cap',
      () {
        final huge = 'X' * 9000;
        const fields = ReportIssueFields(
          whatYouWereDoing: 'doing',
          whatYouExpected: 'expected',
          whatHappened: 'happened',
          errorCode: null,
        );
        final result = IssueUrlBuilder.build(
          fields: fields,
          diagnostic: diagnostic,
          extendedDiagnostic: huge,
        );
        expect(result.plaintextBody, contains('### Extended diagnostic'));
        expect(result.plaintextBody, contains('[diagnostic truncated]'));
        expect(result.plaintextBody, isNot(contains(huge)));
      },
    );

    test('omits the section when null', () {
      const fields = ReportIssueFields(
        whatYouWereDoing: 'doing',
        whatYouExpected: 'expected',
        whatHappened: 'happened',
        errorCode: null,
      );
      final result = IssueUrlBuilder.build(
        fields: fields,
        diagnostic: diagnostic,
      );
      expect(result.plaintextBody, isNot(contains('### Extended diagnostic')));
    });
  });
}
