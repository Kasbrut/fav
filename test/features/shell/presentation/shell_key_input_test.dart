import 'package:fav/features/shell/presentation/shell_key_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyStickyModifiers', () {
    test('ctrl maps letters to their control codes', () {
      expect(applyStickyModifiers('c', ctrl: true, alt: false), '\x03');
      expect(applyStickyModifiers('a', ctrl: true, alt: false), '\x01');
      expect(applyStickyModifiers('z', ctrl: true, alt: false), '\x1a');
      // Uppercase behaves like lowercase, as on a hardware keyboard.
      expect(applyStickyModifiers('C', ctrl: true, alt: false), '\x03');
    });

    test('ctrl maps the standard punctuation controls', () {
      expect(applyStickyModifiers('[', ctrl: true, alt: false), '\x1b');
      expect(applyStickyModifiers(']', ctrl: true, alt: false), '\x1d');
      expect(applyStickyModifiers('_', ctrl: true, alt: false), '\x1f');
      expect(applyStickyModifiers('@', ctrl: true, alt: false), '\x00');
      expect(applyStickyModifiers(' ', ctrl: true, alt: false), '\x00');
    });

    test('alt prefixes the character with ESC', () {
      expect(applyStickyModifiers('b', ctrl: false, alt: true), '\x1bb');
      expect(applyStickyModifiers('.', ctrl: false, alt: true), '\x1b.');
    });

    test('ctrl+alt combines both transformations', () {
      expect(applyStickyModifiers('c', ctrl: true, alt: true), '\x1b\x03');
    });

    test('leaves unmappable ctrl input unchanged', () {
      expect(applyStickyModifiers('7', ctrl: true, alt: false), '7');
      expect(applyStickyModifiers('è', ctrl: true, alt: false), 'è');
    });

    test('leaves multi-character input (paste, IME words) unchanged', () {
      expect(applyStickyModifiers('ls -la', ctrl: true, alt: true), 'ls -la');
    });

    test('is the identity without armed modifiers', () {
      expect(applyStickyModifiers('c', ctrl: false, alt: false), 'c');
    });
  });
}
