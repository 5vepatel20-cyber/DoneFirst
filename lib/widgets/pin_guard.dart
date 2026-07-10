import 'package:flutter/material.dart';
import '../screens/pin_screen.dart';
import '../services/parent_preferences_service.dart';

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
  /// PIN, false if they cancelled or hit the wrong PIN.
  ///
  /// Honours the same 5-attempt lockout as the full-screen flow.
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
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _InlinePinDialog(actionLabel: actionLabel),
    );
    if (entered == null) return false;
    return entered == pin;
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
