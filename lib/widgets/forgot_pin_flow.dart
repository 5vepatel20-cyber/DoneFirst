import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/parent_preferences_service.dart';
import '../utils/pin_strength.dart';

/// "Forgot PIN?" recovery flow.
///
///   • Password-based accounts: parent enters their password →
///     Supabase verifies → pick a new 4-digit PIN. Success
///     returns true; the caller (PinScreen) should pop itself so
///     the user lands back on the dashboard and re-enters via the
///     gate with the new PIN.
///
///   • OAuth-only accounts (Google / Apple): no password to
///     verify, so we tell the parent to sign out and back in.
///     Once they re-authenticate, they can re-enter Settings
///     without any gate (because the PIN will be replaced with
///     whatever's in shared_preferences — which is the same one
///     they forgot, so we still need the recovery step; but the
///     practical UX is "rebuild the PIN from scratch").
///
/// Returns true if the PIN was successfully reset, false if the
/// parent cancelled, entered the wrong password, or the new PIN
/// failed validation.
class ForgotPinFlow {
  const ForgotPinFlow._();

  static Future<bool> run(BuildContext context) async {
    final auth = AuthService();
    final email = auth.currentUser?.email;
    if (email == null || !context.mounted) return false;

    if (!auth.currentUserUsesPassword) {
      await _showOAuthOnlyHelp(context);
      return false;
    }

    // Step 1: verify the password. We pass the email so the
    // dialog doesn't ask for it — the parent's email is the one
    // currently signed in, no need to type it.
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _VerifyPasswordDialog(email: email),
    );
    if (verified != true || !context.mounted) return false;

    // Step 2: pick a new PIN. Same validation as Settings →
    // Change PIN: 4 digits only.
    final newPin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _SetNewPinDialog(),
    );
    // The dialog already validates length + non-triviality via
    // `pinRejectionReason`; if it pops, the value is good. The
    // null check is the only one we still need here.
    if (newPin == null) return false;

    await ParentPreferencesService().setPin(newPin);
    return true;
  }

  static Future<void> _showOAuthOnlyHelp(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Parent PIN'),
        content: const Text(
          'You signed up with a social account, so there is no '
          'password to verify. Sign out and sign back in to clear '
          'the old PIN, then set a new one in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _VerifyPasswordDialog extends StatefulWidget {
  final String email;
  const _VerifyPasswordDialog({required this.email});

  @override
  State<_VerifyPasswordDialog> createState() => _VerifyPasswordDialogState();
}

class _VerifyPasswordDialogState extends State<_VerifyPasswordDialog> {
  final _passwordController = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.verifyPassword(widget.email, password);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // Generic message — don't leak whether the email exists or
      // the password is just wrong.
      if (mounted) {
        setState(() {
          _error = 'Wrong password. Try again.';
          _busy = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Verify your password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter the password for ${widget.email} to reset your '
            'Parent PIN.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}

class _SetNewPinDialog extends StatefulWidget {
  const _SetNewPinDialog();

  @override
  State<_SetNewPinDialog> createState() => _SetNewPinDialogState();
}

class _SetNewPinDialogState extends State<_SetNewPinDialog> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  void _submit() {
    final pin = _controller.text.trim();
    final confirm = _confirmController.text.trim();
    // Reuse the shared weak-PIN validator so the recovery flow
    // and the Settings → Change PIN flow agree on what's "too
    // simple". Without this, a parent could forget their strong
    // PIN, recover with a weak one, and live with that until the
    // next forget — undermining the 5-attempts lockout.
    final rejection = pinRejectionReason(pin);
    if (rejection != null) {
      setState(() => _error = rejection);
      return;
    }
    if (pin != confirm) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set a new Parent PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pick a 4-digit PIN. You\'ll use this to unlock parent '
            'screens.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'New PIN',
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Confirm new PIN',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}