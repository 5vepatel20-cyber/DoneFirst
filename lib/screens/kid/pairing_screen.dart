import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/kid_auth_service.dart';
import '../../theme/app_theme.dart';

/// Full-screen "Enter 6-digit pairing code" form.
///
/// No password — just the six-digit code a parent generates in their
/// DoneFirst app. The six cells are a view over a real (invisible)
/// text field, so entry uses the platform's own numeric keyboard —
/// on iOS that's the system keypad, with the paste/undo behaviour and
/// accessibility support a hand-rolled on-screen pad can't match. The
/// code auto-submits the moment the sixth digit lands.
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
        child: GestureDetector(
          // Tapping anywhere on the page brings the keyboard back if
          // the kid dismissed it.
          onTap: () => _focusNode.requestFocus(),
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              28,
              40,
              28,
              // Keep the cells clear of the system keyboard.
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
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
                _CodeCells(
                  digits: _code,
                  busy: _busy,
                  field: _hiddenField(),
                  onTap: () => _focusNode.requestFocus(),
                ),
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
      ),
    );
  }

  /// The real input. It sits behind the cells at zero opacity rather
  /// than being Offstage — an offstage field can't hold focus, and
  /// focus is what raises the platform keyboard.
  Widget _hiddenField() {
    return Opacity(
      opacity: 0,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        enabled: !_busy,
        // TextInputType.number gives iOS its numeric keypad and
        // Android the digits layout.
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        showCursor: false,
        enableInteractiveSelection: false,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

/// Six rounded cells that fill left-to-right as digits are entered.
/// The next empty cell is ringed in green so kids know where they are.
///
/// Purely a view: [field] is the invisible TextField that actually
/// holds the text, stacked behind the cells so the whole row is one
/// tap target for raising the keyboard.
class _CodeCells extends StatelessWidget {
  final String digits;
  final bool busy;
  final Widget field;
  final VoidCallback onTap;

  const _CodeCells({
    required this.digits,
    required this.busy,
    required this.field,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Sized so the field has a real layout box to focus into
          // without affecting the row's height.
          SizedBox(width: 1, height: 58, child: field),
          _cells(),
        ],
      ),
    );
  }

  Widget _cells() {
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
