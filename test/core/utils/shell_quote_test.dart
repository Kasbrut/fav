import 'package:fav/core/utils/shell_quote.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wraps a plain value in single quotes', () {
    expect(shellSingleQuote('wg0'), "'wg0'");
  });

  test('escapes embedded single quotes so a value cannot break out', () {
    expect(shellSingleQuote("it's"), r"'it'\''s'");
  });

  test('quotes the empty string', () {
    expect(shellSingleQuote(''), "''");
  });

  test('leaves other shell metacharacters inert inside the quotes', () {
    expect(
      shellSingleQuote(r'$(rm -rf /); `x` && $HOME'),
      r"'$(rm -rf /); `x` && $HOME'",
    );
  });
}
