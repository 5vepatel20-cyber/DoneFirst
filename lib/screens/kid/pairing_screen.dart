import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/kid_auth_service.dart';
import '../../theme/app_theme.dart';

/// Full-screen "Enter 6-digit pairing code" form.
///
/// Modeled on the parent app's verify_email_screen.dart — tinted
/// icon disc + screenTitle + body + primary CTA, but with a six-digit
/// numeric input that auto-submits when complete.
///
/// Once pairing succeeds, the parent app's main.dart swaps this out
/// for the appropriate lock state screen.
class PairingScreen extends StatefulWidget {
  /// Called when the kid taps a "I'm not who I'm claimed to be" /
  /// "Sign out" affordance. The kid root uses this to clear the
  /// stored session and bounce back to the auth screen.
  final VoidCallback? onSignOut;

  const PairingScreen({super.key, this.onSignOut});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _auth = KidAuthService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-focus so the soft keyboard pops up on launch — kids
    // shouldn't have to tap the field first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
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
    setState(() {}); // refresh the underline indicator
  }

  Future<void> _pair(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.claimPairingCode(code);
      // Don't navigate from here — main.dart listens on
      // KidAuthService and swaps the screen when isPaired flips.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is KidAuthException ? e.message : 'Could not pair';
        _busy = false;
      });
      // Re-focus so the kid can immediately try a new code.
      _controller.clear();
      _focusNode.requestFocus();
    }
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.kidBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.link,
                    size: 56,
                    color: AppColors.grass,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Pair this device',
                  textAlign: TextAlign.center,
                  style: AppText.title(size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ask a parent to open DoneFirst on their '
                  'phone, then Devices → Pair, and read you '
                  'the 6-digit code.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySecondary(size: 15),
                ),
                const SizedBox(height: 36),
                _CodeField(
                  controller: _controller,
                  focusNode: _focusNode,
                  digits: _code,
                  busy: _busy,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppText.body(color: AppColors.danger),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy || _code.length != 6
                      ? null
                      : () => _pair(_code),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.card,
                          ),
                        )
                      : const Text('Pair'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Codes expire in 10 minutes for security.',
                  textAlign: TextAlign.center,
                  style: AppText.bodySecondary(size: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Six underlined digit slots. Filled digits are grass-green; empty
/// slots are greyed. Tapping the row focuses a hidden text field.
class _CodeField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String digits;
  final bool busy;

  const _CodeField({
    required this.controller,
    required this.focusNode,
    required this.digits,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // The actual TextField is invisible — positioned over the
        // six underlines. We use a transparent field just for the
        // numeric input + autocomplete / paste behavior.
        Opacity(
          opacity: 0,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: !busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              counterText: '',
              filled: false,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 1),
          ),
        ),
        // The visible six-slot row.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            final filled = i < digits.length;
            return Container(
              width: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        filled ? digits[i] : '',
                        style: AppText.code(size: 28),
                      ),
                    ),
                  ),
                  Container(
                    height: 2,
                    margin: const EdgeInsets.only(top: 6),
                    color: filled ? AppColors.grass : AppColors.hair2,
                  ),
                ],
              ),
            );
          }),
        ),
        // Tap-anywhere-to-focus layer. Sits below the TextField above
        // in the Stack (so the TextField still receives the input)
        // — we capture the gesture here to make the whole row
        // tappable for kids with less precise aim.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => focusNode.requestFocus(),
          ),
        ),
      ],
    );
  }
}
