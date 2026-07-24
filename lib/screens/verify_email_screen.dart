import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import 'parent_dashboard.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String password;
  final String displayName;
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.password,
    required this.displayName,
  });

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _auth = AuthService();
  final _sessionService = SessionService();
  bool _checking = false;

  Future<void> _checkVerification() async {
    setState(() => _checking = true);
    // Capture the Navigator + messenger before the first await so the
    // post-await branches don't need a `mounted` guard for the context
    // itself — only the captured handles, which are safe to use as long
    // as the State is still mounted (handled by `if (!mounted) return`).
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = await _auth.signIn(widget.email, widget.password);
      if (user != null && user.emailConfirmedAt != null) {
        await _sessionService.ensureParentRecord(
          user.id,
          widget.email,
          widget.displayName,
        );
        if (!mounted) return;
        navigator.pushReplacement(
          MaterialPageRoute(builder: (_) => const ParentDashboard()),
        );
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _checking = false);
    messenger.showSnackBar(
      const SnackBar(content: Text('Not verified yet. Check your email.')),
    );
  }

  Future<void> _resend() async {
    try {
      await _auth.signIn(widget.email, widget.password);
      await _auth.resendVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email resent!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _skip() async {
    final user = _auth.currentUser;
    if (user != null) {
      await _sessionService.ensureParentRecord(
        user.id,
        widget.email,
        widget.displayName,
      );
    }
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ParentDashboard()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.greenTint,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  LucideIcons.mail,
                  size: 40,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(height: 24),
              Text('Check your inbox', style: AppText.screenTitle()),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  style: AppText.body(size: 15),
                  children: [
                    const TextSpan(text: 'We sent a link to '),
                    TextSpan(
                      text: widget.email,
                      style: AppText.body(
                        size: 15,
                        w: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const TextSpan(text: '. Tap it, then come back here.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              DfButton(
                "I've verified — continue",
                onPressed: _checking ? null : _checkVerification,
                loading: _checking,
                icon: _checking ? null : LucideIcons.refreshCw,
              ),
              const SizedBox(height: 12),
              DfButton.outline(
                'Resend email',
                onPressed: _resend,
                icon: LucideIcons.send,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _skip,
                child: Text(
                  "Skip — I'll verify later",
                  style: AppText.button(color: AppColors.ink45, size: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
