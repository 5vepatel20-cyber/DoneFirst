import 'package:shared_preferences/shared_preferences.dart';

/// Tracks failed PIN attempts for the Parent PIN gate so a kid can't
/// brute-force the 4-digit code by tapping. After [maxAttempts] the
/// gate locks for [lockoutDuration]; once the lockout expires the
/// counter resets.
///
/// Stored locally in SharedPreferences — this protects against a kid
/// at the device, not against someone extracting prefs from disk.
/// The PIN itself is also stored in SharedPreferences (see
/// ParentPreferencesService); the threat model is "kid shouldn't be
/// able to tap through to settings" not "secure against an attacker
/// with shell access". Don't repurpose this for anything that needs
/// real security.
class PinAttemptTracker {
  static const String _attemptsKey = 'pin_attempts_v1';
  static const String _lockoutUntilKey = 'pin_lockout_until_v1';

  /// Max failed attempts before lockout. Five matches the typical
  /// banking-app UX (3 wrong PINs = lock).
  static const int maxAttempts = 5;

  /// How long the gate stays locked once [maxAttempts] is hit.
  static const Duration lockoutDuration = Duration(seconds: 30);

  /// True when a previous string of failures has put us in lockout
  /// and the lockout window hasn't expired yet. Side effect: if the
  /// lockout has expired, this also clears the counter so the next
  /// attempt starts fresh.
  Future<bool> isLockedOut() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_lockoutUntilKey);
    if (until == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= until) {
      // Lockout window passed — reset both the lockout and the
      // attempt counter so the kid gets a fresh 5 tries.
      await prefs.remove(_lockoutUntilKey);
      await prefs.remove(_attemptsKey);
      return false;
    }
    return true;
  }

  /// Seconds remaining on the current lockout window, or 0 if not
  /// locked out (or lockout has expired). Ceiling-rounded so a kid
  /// waiting on the screen sees whole seconds counting down.
  Future<int> remainingLockoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_lockoutUntilKey);
    if (until == null) return 0;
    final remainingMs =
        until - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return 0;
    return (remainingMs / 1000).ceil();
  }

  /// Number of consecutive failed attempts so far in this window.
  /// Resets to 0 once the lockout expires (see [isLockedOut]).
  Future<int> failedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_attemptsKey) ?? 0;
  }

  /// Increments the failed-attempt counter. If this push brings us
  /// to [maxAttempts] (or we're already past it), arms the lockout.
  Future<void> recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_attemptsKey) ?? 0) + 1;
    await prefs.setInt(_attemptsKey, attempts);
    if (attempts >= maxAttempts) {
      final until = DateTime.now().millisecondsSinceEpoch +
          lockoutDuration.inMilliseconds;
      await prefs.setInt(_lockoutUntilKey, until);
    }
  }

  /// Clears the counter and lockout. Called after a successful PIN
  /// entry so the next failure starts at zero.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptsKey);
    await prefs.remove(_lockoutUntilKey);
  }

  /// Test-only escape hatch so we can verify the lockout window
  /// without needing to inject a clock. Production callers should
  /// ignore this; it just lets tests pre-arm a future timestamp
  /// for the lockout expiry.
  Future<void> debugForceClear() => reset();
}
