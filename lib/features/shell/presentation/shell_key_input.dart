/// Applies the extra-keys bar's sticky CTRL/ALT modifiers to [data], the text
/// the soft keyboard produced for one keystroke.
///
/// Mirrors what a hardware keyboard would send: CTRL maps letters to their
/// control codes (`c` → 0x03) and the standard punctuation controls
/// (`@ [ \ ] ^ _` and space); ALT prefixes the character with ESC. Input the
/// mapping does not cover — digits, accented letters, multi-character strings
/// from paste or word-composing IMEs — is returned unchanged, so arming CTRL
/// can never corrupt regular typing.
String applyStickyModifiers(
  String data, {
  required bool ctrl,
  required bool alt,
}) {
  if (data.length != 1) return data;
  var result = data;
  if (ctrl) {
    final code = data.toLowerCase().codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) {
      // a-z → 0x01-0x1a
      result = String.fromCharCode(code - 0x60);
    } else if (code >= 0x5b && code <= 0x5f) {
      // [ \ ] ^ _ → 0x1b-0x1f
      result = String.fromCharCode(code - 0x40);
    } else if (data == '@' || data == ' ') {
      result = '\x00';
    }
  }
  if (alt) result = '\x1b$result';
  return result;
}
