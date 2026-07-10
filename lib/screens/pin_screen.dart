import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pin_attempt_tracker.dart';
import '../theme/app_theme.dart';

/// Gates a screen behind a 4-digit parent PIN. After 5 wrong
/// attempts the gate locks for 30 seconds (see PinAttemptTracker).
///
/// On success: pushes [destination] replacing the current route so
/// Back from the destination doesn't return to the PIN screen. On
/// failure: increments the attempt counter and shows an inline
/// error. On lockout: the TextField is disabled and a countdown
/// shows until the kid can try again.
class PinScreen extends StatefulWidget {
  final String correctPin;
  final Widget destination;
  final String title;

  const PinScreen({
    super.key,
    required this.correctPin,
    required this.destination,
    this.title = 'Parent PIN Required',
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _pinController = TextEditingController();
  final _tracker = PinAttemptTracker();
  bool _error = false;
  bool _lockedOut = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _refreshLockoutState();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _refreshLockoutState() async {
    final locked = await _tracker.isLockedOut();
    final remaining = await _tracker.remainingLockoutSeconds();
    if (!mounted) return;
    setState(() {
      _lockedOut = locked;
      _lockoutSeconds = remaining;
    });
    if (locked && _lockoutTimer == null) {
      _startLockoutCountdown();
    }
  }

  void _startLockoutCountdown() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      final remaining = await _tracker.remainingLockoutSeconds();
      if (!mounted) {
        t.cancel();
        return;
      }
      if (remaining <= 0) {
        t.cancel();
        _lockoutTimer = null;
        await _tracker.reset();
        if (!mounted) return;
        setState(() {
          _lockedOut = false;
          _lockoutSeconds = 0;
          _error = false;
        });
        return;
      }
      setState(() => _lockoutSeconds = remaining);
    });
  }

  Future<void> _submit() async {
    if (_lockedOut) return;
    final entered = _pinController.text.trim();
    if (entered == widget.correctPin) {
      await _tracker.reset();
      if (!mounted) return;
      // Push the destination on top of us so the caller's
      // `.then((_) => ...)` fires when the user finishes with
      // the destination, not just when they typed the PIN.
      // When the destination pops, we pop ourselves too so the
      // user is taken back to whatever was below us (typically
      // the dashboard) in a single Back press.
      final destRoute =
          MaterialPageRoute(builder: (_) => widget.destination);
      Navigator.push(context, destRoute).then((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    await _tracker.recordFailure();
    if (!mounted) return;
    setState(() => _error = true);
    _pinController.clear();
    await _refreshLockoutState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Enter PIN to continue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  maxLength: 4,
                  enabled: !_lockedOut,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: 'PIN',
                    errorText: _lockedOut
                        ? 'Locked — try again in ${_lockoutSeconds}s'
                        : (_error ? 'Incorrect PIN' : null),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _lockedOut ? null : _submit,
                child: const Text('Unlock'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
