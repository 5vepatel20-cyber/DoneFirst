import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import 'parent_dashboard.dart';

/// Captures the COPPA / GDPR-K parental-consent disclosures for a
/// first-time Google sign-in user. Reached from AuthScreen after a
/// successful Google sign-in that yields a freshly-created User.
///
/// Mirrors the consent flow in AuthScreen for password signups so
/// the parent sees the same disclosures regardless of how they
/// authenticated. On completion, navigates to ParentDashboard.
///
/// Decline is final: the Supabase session is signed out and the user
/// returns to /auth, the same as a password-signup declined consent.
class ConsentCaptureScreen extends StatefulWidget {
  final String parentId;
  final String displayName;
  final String email;
  const ConsentCaptureScreen({
    super.key,
    required this.parentId,
    required this.displayName,
    required this.email,
  });

  @override
  State<ConsentCaptureScreen> createState() => _ConsentCaptureScreenState();
}

class _ConsentCaptureScreenState extends State<ConsentCaptureScreen> {
  final _consentService = ConsentService();
  final _sessionService = SessionService();
  final _auth = AuthService();
  final _signatureController = TextEditingController();
  bool _ackAdult = false;
  bool _ackGuardian = false;
  bool _ackChildData = false;
  bool _ackAiVerification = false;
  bool _ackOptionalAnalytics = false;
  bool _submitting = false;
  String? _error;

  bool get _allRequiredAcks =>
      _ackAdult && _ackGuardian && _ackChildData && _ackAiVerification;

  bool get _signatureValid =>
      _signatureController.text.trim().length >= 2 &&
      _signatureController.text.trim().toLowerCase() != 'delete';

  bool get _ready => _allRequiredAcks && _signatureValid;

  String? _readinessError() {
    if (!_ackAdult) return 'Please confirm you are 18 or older.';
    if (!_ackGuardian) {
      return 'Please confirm you are a parent or legal guardian.';
    }
    if (!_ackChildData) {
      return 'Please consent to the data we collect.';
    }
    if (!_ackAiVerification) {
      return 'Please consent to AI proof verification.';
    }
    if (!_signatureValid) {
      return 'Please type your full legal name as your signature.';
    }
    return null;
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final signature = _signatureController.text.trim();
      // Both writes only need widget.parentId. Run them in parallel
      // so the consent best-effort write doesn't block the critical
      // parent-record upsert (and vice versa). catchError on the
      // consent future preserves the original non-fatal semantics.
      final ensureFut = _sessionService.ensureParentRecord(
        widget.parentId,
        widget.email,
        widget.displayName,
      );
      final consentFut = _consentService
          .recordParentalConsent(
            parentId: widget.parentId,
            signedName: signature,
            acknowledgments: {
              'is_adult': _ackAdult,
              'is_guardian': _ackGuardian,
              'consents_child_data': _ackChildData,
              'consents_ai_verification': _ackAiVerification,
              'consents_optional_analytics': _ackOptionalAnalytics,
            },
            consentType: ConsentService.typeAccountCreation,
          )
          .catchError((Object e) {
            debugPrint('Consent record failed (non-fatal): $e');
            return null;
          });
      await ensureFut;
      await consentFut;
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboard()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _submitting = false;
        });
      }
    }
  }

  Future<void> _decline() async {
    // Decline = sign out so the OAuth round-trip's session doesn't
    // leave a half-claimed account behind. Without this the next
    // launch would auto-resume the same Google identity and the
    // parent would loop back to consent forever.
    await _auth.signOut();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('One last step')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.greenTint,
                      borderRadius: BorderRadius.circular(AppRadius.iconTile),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.shieldCheck,
                      color: AppColors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Welcome, ${widget.displayName}',
                      style: AppText.title(size: 21),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Before we add your kids, we need your consent to '
                'collect their homework data and run AI proof '
                'verification. This is required by COPPA / GDPR-K.',
                style: AppText.body(),
              ),
              const SizedBox(height: 22),
              _buildConsentCard(),
              const SizedBox(height: 16),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    border: Border.all(
                      color: AppColors.dangerFg.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        color: AppColors.dangerFg,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: AppText.body(color: AppColors.dangerFg),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null) const SizedBox(height: 16),
              DfButton(
                _ready
                    ? 'I consent — continue'
                    : (_readinessError() ?? 'Continue'),
                onPressed: !_ready || _submitting ? null : _submit,
                loading: _submitting,
                icon: _ready ? LucideIcons.check : null,
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _submitting ? null : _decline,
                  child: Text(
                    'Decline — sign out',
                    style: AppText.body(color: AppColors.ink45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsentCard() {
    final allChecked = _allRequiredAcks;
    return DfCard(
      padding: EdgeInsets.zero,
      borderColor: allChecked ? AppColors.green.withValues(alpha: 0.5) : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Row(
              children: [
                Icon(
                  allChecked ? LucideIcons.badgeCheck : LucideIcons.scale,
                  color: allChecked ? AppColors.green : AppColors.ink45,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Parental Consent (required)',
                    style: AppText.cardHeader(size: 15),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPadding,
              vertical: 6,
            ),
            child: Column(
              children: [
                _ackTile(
                  value: _ackAdult,
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _ackAdult = v ?? false),
                  title: 'I am 18 or older.',
                  subtitle: 'Required for COPPA / GDPR-K.',
                ),
                _ackTile(
                  value: _ackGuardian,
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _ackGuardian = v ?? false),
                  title:
                      'I am the parent or legal guardian of any child I add.',
                  subtitle:
                      'DoneFirst only collects data on children whose legal parent or guardian uses this account.',
                ),
                _ackTile(
                  value: _ackChildData,
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _ackChildData = v ?? false),
                  title:
                      'I consent to DoneFirst storing photos of my child\'s homework and basic profile info.',
                  subtitle: 'Photos are stored privately and never shared.',
                ),
                _ackTile(
                  value: _ackAiVerification,
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _ackAiVerification = v ?? false),
                  title:
                      'I consent to AI proof verification (Mistral) reviewing my child\'s submitted photos.',
                  subtitle:
                      'Verification runs on the first photo and the result is shown to you.',
                ),
                _ackTile(
                  value: _ackOptionalAnalytics,
                  onChanged: _submitting
                      ? null
                      : (v) =>
                            setState(() => _ackOptionalAnalytics = v ?? false),
                  title:
                      '(Optional) Share anonymous usage stats so we can improve DoneFirst.',
                  subtitle:
                      'You can change this anytime in Settings. Off by default.',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.cardPadding,
              10,
              AppSpacing.cardPadding,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Type your full legal name as your signature:',
                  style: AppText.body(size: 13, w: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _signatureController,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. Jane Patel',
                    suffixIcon: _signatureValid
                        ? const Icon(
                            LucideIcons.check,
                            color: AppColors.green,
                            size: 18,
                          )
                        : null,
                  ),
                  style: AppText.body(size: 14),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Policy ${ConsentService.currentPolicyVersion}. '
                  'You can view the full policy in Settings after signing up.',
                  style: AppText.caption(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ackTile({
    required bool value,
    required ValueChanged<bool?>? onChanged,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.green,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.body(size: 13, w: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.caption()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
