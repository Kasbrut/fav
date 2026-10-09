import 'package:fav/core/utils/equality.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the [listEquals] helper.
void main() {
  test('identical and null lists', () {
    const list = [1, 2, 3];
    expect(listEquals(list, list), isTrue);
    expect(listEquals<int>(null, null), isTrue);
    expect(listEquals(null, const [1]), isFalse);
    expect(listEquals(const [1], null), isFalse);
  });

  test('compares length and elements', () {
    expect(listEquals(const [1, 2], const [1, 2]), isTrue);
    expect(listEquals(const [1, 2], const [1, 2, 3]), isFalse);
    expect(listEquals(const [1, 2], const [1, 3]), isFalse);
  });
}
