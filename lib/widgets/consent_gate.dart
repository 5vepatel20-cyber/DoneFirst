import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../utils/policy_text.dart';
import '../theme/app_theme.dart';

/// Gates a screen behind a current-policy-version check.
///
/// Wrap any screen where the user is actively using the app
/// (typically the parent dashboard). On every build:
///   1. Asynchronously check whether the signed-in parent has
///      consented to the current [ConsentService.currentPolicyVersion].
///   2. If yes, render [child] as normal.
///   3. If no, show a modal-style dialog with the updated policy
///      and three actions: review the full text, accept (records a
///      new consent row), or sign out (the only way to leave
///      without accepting).
///
/// We can't block the screen from rendering entirely because that
/// would mean a black screen for the duration of the network
/// check. Instead we render the screen normally and overlay the
/// dialog if needed — the user is blocked from interacting with
/// the screen behind the modal because the dialog uses
/// `barrierDismissible: false`.
///
/// This widget is intentionally non-blocking on the result of the
/// check, so a slow network doesn't make the app feel broken.
class ConsentGate extends StatefulWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  final _consentService = ConsentService();
  final _auth = AuthService();
  bool _checking = true;
  bool _needsConsent = false;

  @override
  void initState() {
    super.initState();
    _checkConsent();
  }

  Future<void> _checkConsent() async {
    final user = _auth.currentUser;
    if (user == null) {
      // No user — should never happen if this is mounted after
      // sign-in, but be safe.
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      final needs = await _consentService.needsReConsent(user.id);
      if (!mounted) return;
      setState(() {
        _needsConsent = needs;
        _checking = false;
      });
      if (needs) {
        // Defer the dialog to the next frame so the screen has
        // time to render first. Otherwise the dialog appears on
        // top of a blank canvas.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showConsentDialog();
        });
      }
    } catch (_) {
      // If the check fails (network, DB), don't block the user.
      // The original signup consent is enough.
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showConsentDialog() async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Updated Privacy Policy'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Our privacy policy has been updated. Please review the '
                'changes and accept the new policy to continue using '
                'DoneFirst.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current policy version: '
                      '${ConsentService.currentPolicyVersion}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your previous consent has been recorded and is '
                      'available in Settings → Consent Audit.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _showFullPolicy(ctx),
            child: const Text('Read Full Policy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              await _signOut();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sign Out'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await _consentService.recordConsent(
                  parentId: _auth.currentUser!.id,
                  consentType: ConsentService.typePolicyUpdate,
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Could not record consent: $e')),
                  );
                }
              }
            },
            child: const Text('I Accept'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      setState(() => _needsConsent = false);
    } else if (accepted == false && mounted) {
      // User chose sign out — _signOut has already navigated.
    }
  }

  void _showFullPolicy(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (c2) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(c2),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      kPrivacyPolicyText,
                      style: const TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/auth', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We don't actually gate the build — the modal dialog does the
    // gating visually with barrierDismissible: false. The check
    // flag is unused for now; we keep the state for future
    // tightening (e.g. showing a loading ring until the check
    // resolves).
    assert(!_checking || !_needsConsent);
    return widget.child;
  }
}
