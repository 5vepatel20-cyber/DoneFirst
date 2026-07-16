import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/auth_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
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
    try {
      final user = await _auth.signIn(widget.email, widget.password);
      if (user != null && user.emailConfirmedAt != null && mounted) {
        await _sessionService.ensureParentRecord(
          user.id,
          widget.email,
          widget.displayName,
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboard()),
        );
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not verified yet. Check your email.')),
      );
    }
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.mailWarning,
                  size: 48,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                style: AppText.title(size: 24),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a verification link to\n${widget.email}',
                textAlign: TextAlign.center,
                style: AppText.bodySecondary(size: 15),
              ),
              const SizedBox(height: 8),
              Text(
                'Click the link in the email, then come back.',
                textAlign: TextAlign.center,
                style: AppText.bodySecondary(size: 13),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _checking ? null : _checkVerification,
                icon: _checking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('I\'ve Verified — Continue'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _resend,
                icon: const Icon(LucideIcons.send, size: 18),
                label: const Text('Resend Email'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _skip,
                child: Text(
                  'Skip — I\'ll verify later',
                  style: AppText.button(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
