import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/kid_auth_service.dart';
import '../../theme/app_theme.dart';

/// Full-screen "Enter 6-digit pairing code" form.
///
/// No password — just the six-digit code a parent generates in their
/// DoneFirst app. A custom on-screen number pad drives a hidden
/// controller so kids never see a full keyboard; the code auto-submits
/// the moment the sixth digit lands.
///
/// Once pairing succeeds, the parent app's main.dart swaps this out
/// for the appropriate lock state screen.
class PairingScreen extends StatefulWidget {
  /// Called when the kid taps a "I'm not who I'm claimed to be" /
  /// "Sign out" affordance. The kid root uses this to clear the
  /// stored session and bounce back to the auth screen.
  final VoidCallback? onSignOut;

  /// The shared KidAuthService instance. PairingScreen uses this
  /// (instead of creating its own) so that after pairing succeeds
  /// the global instance's _childId is set and KidRoot's isPaired
  /// check flips correctly.
  final KidAuthService authService;

  const PairingScreen({super.key, this.onSignOut, required this.authService});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  void _onChange() {
    // Strip non-digits (kids might paste code with a space) and
    // truncate to 6 chars. Auto-submit once length is exactly 6.
    final raw = _controller.text;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits != raw) {
      _controller.value = _controller.value.copyWith(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
      return;
    }
    if (digits.length >= 6) {
      final code = digits.substring(0, 6);
      _controller.value = _controller.value.copyWith(
        text: code,
        selection: TextSelection.collapsed(offset: 6),
      );
      if (!_busy && _error == null && mounted) {
        _pair(code);
      }
    }
    setState(() {}); // refresh the cells
  }

  Future<void> _pair(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.claimPairingCode(code);
      // Don't navigate from here — main.dart listens on
      // KidAuthService and swaps the screen when isPaired flips.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is KidAuthException ? e.message : 'Could not pair';
        _busy = false;
      });
      // Clear so the kid can immediately try a new code.
      _controller.clear();
    }
  }

  // On-screen pad → drives [_controller]; its listener handles
  // truncation + auto-submit so entry behaves the same as a paste.
  void _tapDigit(String d) {
    if (_busy) return;
    setState(() => _error = null);
    final cur = _controller.text;
    if (cur.length >= 6) return;
    _controller.text = cur + d;
  }

  void _backspace() {
    if (_busy) return;
    final cur = _controller.text;
    if (cur.isEmpty) return;
    _controller.text = cur.substring(0, cur.length - 1);
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _code => _controller.text;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 40, 28, 8),
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: const BoxDecoration(
                        color: AppColors.greenTint,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.link,
                        size: 40,
                        color: AppColors.green,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Enter your code',
                      textAlign: TextAlign.center,
                      style: AppText.title(size: 26),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ask a parent for the 6-digit code from their '
                      'DoneFirst app.',
                      textAlign: TextAlign.center,
                      style: AppText.body(size: 15),
                    ),
                    const SizedBox(height: 32),
                    _CodeCells(digits: _code, busy: _busy),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 24,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: AppColors.green,
                              ),
                            )
                          : (_error != null
                                ? Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: AppText.body(
                                      size: 14,
                                      color: AppColors.danger,
                                    ),
                                  )
                                : Text(
                                    'Codes expire 10 minutes after they\'re made.',
                                    textAlign: TextAlign.center,
                                    style: AppText.bodySecondary(size: 12.5),
                                  )),
                    ),
                  ],
                ),
              ),
            ),
            _NumberPad(
              onDigit: _tapDigit,
              onBackspace: _backspace,
              enabled: !_busy,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Six rounded cells that fill left-to-right as digits are entered.
/// The next empty cell is ringed in green so kids know where they are.
class _CodeCells extends StatelessWidget {
  final String digits;
  final bool busy;

  const _CodeCells({required this.digits, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final filled = i < digits.length;
        final isNext = i == digits.length && !busy;
        return Container(
          width: 46,
          height: 58,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          decoration: BoxDecoration(
            color: filled ? AppColors.greenTint : AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(
              color: filled
                  ? AppColors.green
                  : (isNext ? AppColors.green : AppColors.borderCol),
              width: filled || isNext ? 1.8 : 1.2,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            filled ? digits[i] : '',
            style: AppText.code(size: 26, color: AppColors.ink),
          ),
        );
      }),
    );
  }
}

/// Calm on-screen number pad: 1-9, then a blank, 0, and backspace.
class _NumberPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  const _NumberPad({
    required this.onDigit,
    required this.onBackspace,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Widget? icon}) {
      final interactive = enabled && onTap != null;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: GestureDetector(
            onTap: interactive ? onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 58,
              decoration: BoxDecoration(
                color: label.isEmpty && icon == null
                    ? Colors.transparent
                    : AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.tile),
                border: label.isEmpty && icon == null
                    ? null
                    : Border.all(color: AppColors.borderCol),
              ),
              alignment: Alignment.center,
              child:
                  icon ??
                  Text(
                    label,
                    style: AppText.title(size: 24, color: AppColors.ink),
                  ),
            ),
          ),
        ),
      );
    }

    Widget row(List<Widget> children) => Row(children: children);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row([
            key('1', onTap: () => onDigit('1')),
            key('2', onTap: () => onDigit('2')),
            key('3', onTap: () => onDigit('3')),
          ]),
          row([
            key('4', onTap: () => onDigit('4')),
            key('5', onTap: () => onDigit('5')),
            key('6', onTap: () => onDigit('6')),
          ]),
          row([
            key('7', onTap: () => onDigit('7')),
            key('8', onTap: () => onDigit('8')),
            key('9', onTap: () => onDigit('9')),
          ]),
          row([
            key(''),
            key('0', onTap: () => onDigit('0')),
            key(
              '',
              onTap: onBackspace,
              icon: const Icon(
                LucideIcons.delete,
                size: 24,
                color: AppColors.ink70,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
