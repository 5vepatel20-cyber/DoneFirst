import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/pin_attempt_tracker.dart';
import '../theme/app_theme.dart';
import '../widgets/forgot_pin_flow.dart';

/// Gates a screen behind a 4-digit parent PIN. After 5 wrong
/// attempts the gate locks for 30 seconds (see PinAttemptTracker).
///
/// Layout follows the handoff:
///   - Back arrow + centered key icon tile (sageFill)
///   - "Enter parent PIN" 27px Bricolage
///   - 4 dot indicators (filled forest as the parent types)
///   - Custom numeric keypad (1–9, blank, 0, backspace) — each key
///     is a white rounded tile with a Bricolage digit + tiny letter
///     subtitle (abc, def, …) matching the iOS numeric pad
///   - Forgot PIN? link below the keypad
///
/// On success: pushes [destination] replacing the current route so
/// Back from the destination doesn't return to the PIN screen.
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
  // _entered holds the 0-4 chars typed so far. We render dots from
  // this rather than from a TextField so the keypad fully owns
  // input — no system keyboard pops up.
  String _entered = '';
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

  Future<void> _onDigit(String d) async {
    if (_lockedOut || _entered.length >= 4) return;
    setState(() {
      _entered = _entered + d;
      _error = false;
    });
    if (_entered.length == 4) {
      // Tiny delay so the 4th dot fills before the screen transitions.
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _submit();
    }
  }

  void _onBackspace() {
    if (_lockedOut || _entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = false;
    });
  }

  Future<void> _submit() async {
    if (_lockedOut) return;
    if (_entered == widget.correctPin) {
      await _tracker.reset();
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => widget.destination),
      ).then((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }
    await _tracker.recordFailure();
    if (!mounted) return;
    setState(() {
      _error = true;
      _entered = '';
    });
    await _refreshLockoutState();
  }

  Future<void> _forgotPin() async {
    if (_lockedOut) return;
    final reset = await ForgotPinFlow.run(context);
    if (!mounted) return;
    if (reset) {
      await _tracker.reset();
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // Key icon tile — sageFill background per handoff.
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.sageFill,
                  borderRadius: BorderRadius.circular(AppRadius.iconTile),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.key,
                  size: 28,
                  color: AppColors.forest,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Enter parent PIN',
                style: GoogleFonts.bricolageGrotesque(
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Required to manage parent settings',
                style: AppText.bodySecondary(),
              ),
              const SizedBox(height: 28),
              // 4 dot indicators. Filled = entered; current = sage;
              // empty = faint.
              _PinDots(entered: _entered.length, error: _error),
              const SizedBox(height: 12),
              // Inline error message — appears below the dots, not
              // blocking the keypad so the parent can keep typing.
              SizedBox(
                height: 18,
                child: _buildStatusLine(),
              ),
              const SizedBox(height: 16),
              _NumPad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                disabled: _lockedOut,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _lockedOut ? null : _forgotPin,
                child: Text(
                  'Forgot PIN?',
                  style: AppText.body(color: AppColors.forest),
                ),
              ),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusLine() {
    if (_lockedOut) {
      return Text(
        'Locked — try again in ${_lockoutSeconds}s',
        style: AppText.bodySecondary(color: AppColors.danger, size: 12),
      );
    }
    if (_error) {
      return Text(
        'Incorrect PIN. Try again.',
        style: AppText.bodySecondary(color: AppColors.danger, size: 12),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 4 dot indicators. Filled forest when typed; current dot shows
/// sage to suggest the next tap. Error state shakes the row briefly.
class _PinDots extends StatefulWidget {
  final int entered;
  final bool error;

  const _PinDots({required this.entered, required this.error});

  @override
  State<_PinDots> createState() => _PinDotsState();
}

class _PinDotsState extends State<_PinDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(covariant _PinDots old) {
    super.didUpdateWidget(old);
    if (widget.error && !old.error) {
      _shake
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (_, child) {
        // Three quick back-and-forths in 320ms.
        final dx = _shake.value == 0
            ? 0.0
            : (4 * (1 - _shake.value) *
                    (((_shake.value * 12).floor() % 2) == 0 ? 1 : -1))
                .toDouble();
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < widget.entered;
          return Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: filled ? AppColors.forest : Colors.transparent,
              border: Border.all(
                color: filled ? AppColors.forest : AppColors.faint,
                width: 1.5,
              ),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}

/// Custom 3x4 numeric keypad. Layout:
///   1  2  3
///   4  5  6
///   7  8  9
///   _  0  ⌫
///
/// Each digit key shows the number in Bricolage w700 with a tiny
/// letter subtitle (abc, def, …) under it — matches the iOS-style
/// phone keypad and gives the parent muscle-memory cues for
/// typing without looking.
class _NumPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool disabled;

  const _NumPad({
    required this.onDigit,
    required this.onBackspace,
    required this.disabled,
  });

  static const _digits = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['', '0', 'back'],
  ];

  // Letter subtitles below the digit, matching the phone-pad
  // convention. Empty string for keys that don't need one.
  static const _subtitles = {
    '1': '',
    '2': 'abc',
    '3': 'def',
    '4': 'ghi',
    '5': 'jkl',
    '6': 'mno',
    '7': 'pqrs',
    '8': 'tuv',
    '9': 'wxyz',
    '0': '',
  };

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _digits.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((d) {
              if (d.isEmpty) {
                return const SizedBox(width: 72, height: 72);
              }
              if (d == 'back') {
                return _PadButton(
                  onTap: disabled ? null : onBackspace,
                  child: const Icon(
                    LucideIcons.delete,
                    size: 22,
                    color: AppColors.ink,
                  ),
                );
              }
              return _PadButton(
                onTap: disabled ? null : () => onDigit(d),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: AppColors.ink,
                      ),
                    ),
                    if (_subtitles[d]!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _subtitles[d]!,
                          style: AppText.eyebrow(),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _PadButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: disabled ? AppColors.disabled : AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}