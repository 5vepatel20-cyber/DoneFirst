/// Minimal rules for rejecting trivially-guessable 4-digit parent
/// PINs. Exists separately from the settings/forgot-pin screens so
/// both code paths can share one validator.
///
/// Bar is "reject what a 5-year-old would guess", not "implement
/// NIST". We deliberately don't try to fingerprint the parent's
/// birth year or anniversary — false sense of "smart PIN" + extra
/// friction.
library;

final RegExp _fourDigitsRegex = RegExp(r'^\d{4}$');
final RegExp _allSameRegex = RegExp(r'^(\d)\1{3}$');

/// True iff [pin] is a valid 4-digit parent PIN. Rejects:
///   • non-4-digit strings,
///   • all-same digits (0000, 1111, …),
///   • 4-in-a-row ascending or descending (1234, 4321, 5678, …).
bool isValidParentPin(String pin) {
  if (!_fourDigitsRegex.hasMatch(pin)) return false;
  if (_allSameRegex.hasMatch(pin)) return false;
  final digits = pin.codeUnits;
  final ascending = digits[1] - digits[0] == 1 &&
      digits[2] - digits[1] == 1 &&
      digits[3] - digits[2] == 1;
  final descending = digits[0] - digits[1] == 1 &&
      digits[1] - digits[2] == 1 &&
      digits[2] - digits[3] == 1;
  return !(ascending || descending);
}

/// Human-readable reason [isValidParentPin] would reject [pin], or
/// null if the pin is fine. Used by SnackBar text in both the
/// Settings → Set PIN dialog and the Forgot PIN recovery flow.
String? pinRejectionReason(String pin) {
  if (pin.length != 4) return 'PIN must be 4 digits.';
  if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
    return 'PIN must be 4 digits.';
  }
  if (!isValidParentPin(pin)) {
    return 'PIN too simple — avoid 0000, 1234, or four of the same digit.';
  }
  return null;
}
