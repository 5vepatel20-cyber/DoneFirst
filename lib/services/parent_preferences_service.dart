import 'package:shared_preferences/shared_preferences.dart';

/// Per-parent single-device preferences that aren't worth their own
/// service: parent PIN (locks settings / dashboard behind a 4-digit
/// code), the auto-approve-math flag (skips parental review when
/// Mistral detects math homework), and the default session length
/// pre-selected on LockConfigScreen.
///
/// Storage layout: three separate keys so we don't break old installs
/// when one of the three is removed or renamed. Defaults match what
/// SettingsScreen showed before persistence existed (no PIN, no
/// auto-approve, 60-minute default).
class ParentPreferencesService {
  static const String _pinKey = 'parent_pin_v1';
  static const String _autoApproveMathKey = 'auto_approve_math_v1';
  static const String _defaultMinutesKey = 'default_minutes_v1';

  static const int defaultMinutes = 60;
  static const List<int> allowedMinutes = [30, 60, 90, 120];

  /// Returns the saved PIN or null if not set. Stored as plaintext
  /// SharedPreferences value — same as the original in-memory version,
  /// which means the PIN is a "kid won't accidentally tap" gate, not
  /// a real security boundary. Don't use for anything sensitive.
  Future<String?> getPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey);
    if (pin == null || pin.length != 4) return null;
    return pin;
  }

  Future<void> setPin(String? pin) async {
    final prefs = await SharedPreferences.getInstance();
    if (pin == null) {
      await prefs.remove(_pinKey);
    } else {
      await prefs.setString(_pinKey, pin);
    }
  }

  Future<bool> getAutoApproveMath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoApproveMathKey) ?? false;
  }

  Future<void> setAutoApproveMath(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoApproveMathKey, enabled);
  }

  /// Returns the saved default session length, clamped to the closest
  /// allowed option. Falling back to [defaultMinutes] when nothing is
  /// stored means new parents see 60m on first launch.
  Future<int> getDefaultMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_defaultMinutesKey) ?? defaultMinutes;
    if (!allowedMinutes.contains(stored)) {
      // Clamp to the closest allowed option so an out-of-range value
      // (older build, manually-edited prefs) still produces a usable
      // SegmentedButton selection.
      return _nearest(stored, allowedMinutes);
    }
    return stored;
  }

  Future<void> setDefaultMinutes(int minutes) async {
    final clamped = allowedMinutes.contains(minutes)
        ? minutes
        : _nearest(minutes, allowedMinutes);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_defaultMinutesKey, clamped);
  }

  static int _nearest(int value, List<int> options) {
    var best = options.first;
    var bestDelta = (value - best).abs();
    for (final o in options.skip(1)) {
      final d = (value - o).abs();
      if (d < bestDelta) {
        best = o;
        bestDelta = d;
      }
    }
    return best;
  }
}
