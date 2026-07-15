import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/pin_screen.dart';
import '../services/parent_preferences_service.dart';
import '../services/pin_attempt_tracker.dart';

/// Gates [destination] behind the parent PIN. Three cases:
///
///   • No PIN set yet → push [destination] directly. The first time
///     a parent needs to gate something, they should run through
///     the unprotected destination once and set a PIN in Settings.
///   • PIN set → push PinScreen, which on success pushes
///     [destination]. PinScreen owns the attempt counter and
///     lockout window so this helper stays a thin shell.
///
/// Use [push] from any `onPressed` instead of inlining the route
/// logic — that keeps the "should this screen be gated?" question
/// in one place. If a future screen should be ungated, change it
/// back to a plain Navigator.push; you don't have to remember to
/// unwrap a widget.
///
/// For sensitive one-tap actions that don't warrant a full screen,
/// use [confirmInline] instead. It shares the same
/// [PinAttemptTracker] counter so a kid can't brute-force the 4-digit
/// PIN by alternating between the full-screen gate and the inline
/// prompts — every wrong entry, anywhere, counts toward the lockout.
class PinGuard {
  const PinGuard._();

  /// Push [destination], gated behind the parent PIN if one is set.
  static Future<void> push(
    BuildContext context, {
    required Widget destination,
    String title = 'Parent PIN Required',
  }) async {
    final prefs = ParentPreferencesService();
    final pin = await prefs.getPin();
    if (!context.mounted) return;
    if (pin == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PinScreen(
          correctPin: pin,
          destination: destination,
          title: title,
        ),
      ),
    );
  }

  /// Inline PIN check for sensitive actions that don't deserve a
  /// full screen of their own (e.g. the Delete Account tile in
  /// Settings). Returns true if the parent entered the correct
  /// PIN, false if they cancelled, hit the wrong PIN, or the gate
  /// was locked out.
  ///
  /// Honours the same 5-attempt lockout as the full-screen flow
  /// (see PinAttemptTracker). The previous version of this code
  /// claimed lockout support in a comment but never actually
  /// wired it up — a kid could brute-force the 4-digit PIN via
  /// repeated Delete Account taps with no rate limit.
  static Future<bool> confirmInline(
    BuildContext context, {
    String actionLabel = 'Continue',
  }) async {
    final prefs = ParentPreferencesService();
    final pin = await prefs.getPin();
    if (pin == null) {
      // No PIN set — there's no gate to apply. Caller may want to
      // also prompt to set one, but that's outside this helper's
      // job.
      return true;
    }
    if (!context.mounted) return false;
    final tracker = PinAttemptTracker();
    if (await tracker.isLockedOut()) {
      // Surface the existing lockout to the user without re-opening
      // the dialog — the kid is locked out and there's nothing to
      // type. Returning false makes the caller a no-op; the parent
      // (who shouldn't be locked out under normal use) can come back
      // when the window expires.
      final remaining = await tracker.remainingLockoutSeconds();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Too many wrong PINs. Try again in ${remaining}s.',
            ),
          ),
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _InlinePinDialog(actionLabel: actionLabel),
    );
    if (entered == null) return false;
    if (entered == pin) {
      await tracker.reset();
      return true;
    }
    // Wrong PIN — record the failure so the next confirmInline
    // call sees the incremented counter and (eventually) the
    // lockout kicks in.
    await tracker.recordFailure();
    if (await tracker.isLockedOut()) {
      // Hit the threshold on this very attempt. Tell the parent
      // what just happened.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Too many wrong PINs. Locked for 30s.'),
          ),
        );
      }
    } else if (context.mounted) {
      final failedAttempts = await tracker.failedAttempts();
      final remaining =
          PinAttemptTracker.maxAttempts - failedAttempts;
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wrong PIN. $remaining ${remaining == 1 ? "try" : "tries"} left.'),
        ),
      );
    }
    return false;
  }
}

class _InlinePinDialog extends StatefulWidget {
  final String actionLabel;
  const _InlinePinDialog({required this.actionLabel});

  @override
  State<_InlinePinDialog> createState() => _InlinePinDialogState();
}

class _InlinePinDialogState extends State<_InlinePinDialog> {
  final _controller = TextEditingController();
  String? _error;

  void _submit() {
    final pin = _controller.text.trim();
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      setState(() => _error = 'PIN must be 4 digits');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm Parent PIN'),
      content: TextField(
        controller: _controller,
        obscureText: true,
        maxLength: 4,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(
          labelText: '4-digit PIN',
          errorText: _error,
          counterText: '',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
