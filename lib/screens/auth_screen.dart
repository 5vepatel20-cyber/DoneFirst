import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/error_banner.dart';
import 'parent_dashboard.dart';
import 'verify_email_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = AuthService();
  final _sessionService = SessionService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _signatureController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;
  bool _obscurePassword = true;
  // Per-item acknowledgments captured during signup. Each entry
  // describes a single disclosure the parent is consenting to. We
  // persist all of them as a JSONB map with recordParentalConsent so
  // the audit trail can show exactly what they agreed to.
  bool _ackAdult = false;
  bool _ackGuardian = false;
  bool _ackChildData = false;
  bool _ackAiVerification = false;
  bool _ackOptionalAnalytics = false;
  // Whether the consent section is expanded. Defaults to true on
  // signup so the parent sees the disclosures before typing.
  bool _consentExpanded = true;
  final _consentService = ConsentService();

  bool get _allRequiredAcks =>
      _ackAdult && _ackGuardian && _ackChildData && _ackAiVerification;

  bool get _signatureValid =>
      _signatureController.text.trim().length >= 2 &&
      _signatureController.text.trim().toLowerCase() != 'delete';

  bool get _signUpReady =>
      _allRequiredAcks && _signatureValid;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUp && !_signUpReady) {
      setState(() {
        _error = _signUpReadinessError();
      });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        final user = await _auth.signUp(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
        );
        if (user != null) {
          await _sessionService.ensureParentRecord(
            user.id,
            _emailController.text.trim(),
            _nameController.text.trim(),
          );
          // Record the full consent capture. Failure is non-fatal so a
          // transient DB error doesn't lose the freshly-created
          // account — we'll re-record at next login if needed.
          try {
            await _consentService.recordParentalConsent(
              parentId: user.id,
              signedName: _signatureController.text,
              acknowledgments: {
                'is_adult': _ackAdult,
                'is_guardian': _ackGuardian,
                'consents_child_data': _ackChildData,
                'consents_ai_verification': _ackAiVerification,
                'consents_optional_analytics': _ackOptionalAnalytics,
              },
              consentType: ConsentService.typeAccountCreation,
            );
          } catch (e) {
            debugPrint('Consent record failed (non-fatal): $e');
          }
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => VerifyEmailScreen(
                  email: _emailController.text.trim(),
                  password: _passwordController.text,
                  displayName: _nameController.text.trim(),
                ),
              ),
            );
          }
          return;
        }
      } else {
        await _auth.signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboard()),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Human-readable explanation of why the Sign Up button is disabled.
  String _signUpReadinessError() {
    if (!_ackAdult) {
      return 'Please confirm you are 18 or older.';
    }
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
    return 'Please complete the consent section above.';
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    final error = Validators.email(email);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    try {
      await _auth.resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reset link sent to $email')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'DoneFirst',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Homework first. Apps after.',
                  style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 32),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ErrorBanner(
                      message: _error!,
                      onDismiss: () => setState(() => _error = null),
                    ),
                  ),
                if (_isSignUp)
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Your Name',
                      prefixIcon: Icon(Icons.person),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: Validators.name,
                  ),
                if (_isSignUp) const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: Validators.email,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  validator: _isSignUp ? Validators.password : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_isSignUp) ...[
                  const SizedBox(height: 16),
                  _buildConsentCard(),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: (_loading ||
                          (_isSignUp && !_signUpReady))
                      ? null
                      : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                ),
                if (!_isSignUp) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _loading ? null : _resetPassword,
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => setState(() {
                    _isSignUp = !_isSignUp;
                    _error = null;
                  }),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "New? Create an account",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  /// Parental consent capture card. Required checkboxes plus a typed
  /// signature. The expansion state persists for the duration of the
  /// signup form so parents can review the disclosures, then collapse
  /// the card to focus on the form fields.
  Widget _buildConsentCard() {
    final allChecked = _allRequiredAcks;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: allChecked
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.textSecondary.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _consentExpanded = !_consentExpanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    allChecked ? Icons.verified_outlined : Icons.gavel,
                    color: allChecked
                        ? AppColors.success
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Parental Consent (required)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _consentExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_consentExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                children: [
                  _ackTile(
                    value: _ackAdult,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _ackAdult = v ?? false),
                    title: 'I am 18 or older.',
                    subtitle: 'Required for COPPA / GDPR-K.',
                  ),
                  _ackTile(
                    value: _ackGuardian,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _ackGuardian = v ?? false),
                    title:
                        'I am the parent or legal guardian of any child I add.',
                    subtitle:
                        'DoneFirst only collects data on children whose legal parent or guardian uses this account.',
                  ),
                  _ackTile(
                    value: _ackChildData,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _ackChildData = v ?? false),
                    title:
                        'I consent to DoneFirst storing photos of my child\'s homework and basic profile info.',
                    subtitle:
                        'Photos are stored privately and never shared.',
                  ),
                  _ackTile(
                    value: _ackAiVerification,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _ackAiVerification = v ?? false),
                    title:
                        'I consent to AI proof verification (Mistral) reviewing my child\'s submitted photos.',
                    subtitle:
                        'Verification runs on the first photo and the result is shown to you.',
                  ),
                  _ackTile(
                    value: _ackOptionalAnalytics,
                    onChanged: _loading
                        ? null
                        : (v) => setState(
                              () => _ackOptionalAnalytics = v ?? false,
                            ),
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Type your full legal name as your signature:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _signatureController,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'e.g. Jane Patel',
                      border: const OutlineInputBorder(),
                      suffixIcon: _signatureValid
                          ? const Icon(
                              Icons.check,
                              color: AppColors.success,
                              size: 18,
                            )
                          : null,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Policy ${ConsentService.currentPolicyVersion}. '
                    'You can view the full policy in Settings after signing up.',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    return CheckboxListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 12)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 10),
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
    );
  }
}
