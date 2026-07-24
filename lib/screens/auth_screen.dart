import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/brand_logo.dart';
import '../widgets/df_kit.dart';
import '../widgets/error_banner.dart';
import 'consent_capture_screen.dart';
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

  bool get _signUpReady => _allRequiredAcks && _signatureValid;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUp && !_signUpReady) {
      setState(() {
        _error = _signUpReadinessError();
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_isSignUp) {
        final user = await _auth.signUp(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
        );
        if (user != null) {
          // Both follow-up writes only depend on user.id, not on each
          // other. Kick them off in parallel so the critical-path
          // (ensureParentRecord) doesn't have to wait for the
          // best-effort (recordParentalConsent). The consent future
          // catches its own errors so a transient DB hiccup there
          // doesn't abort the parent-record insert.
          final ensureFut = _sessionService.ensureParentRecord(
            user.id,
            _emailController.text.trim(),
            _nameController.text.trim(),
          );
          final consentFut = _consentService
              .recordParentalConsent(
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reset link sent to $email')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  /// Triggers the Google sign-in flow. After Supabase returns a
  /// User, routes first-time Google users to the consent capture
  /// screen, returning users straight to the dashboard.
  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await _auth.signInWithGoogle();
      if (!mounted) return;
      // Web OAuth is async via redirect — on the initial tap there
      // is no User yet. AuthScreen will be torn down by the redirect;
      // on return, main.dart's EntryPoint routes to /dashboard
      // directly because _auth.currentUser is non-null.
      if (user == null) {
        if (kIsWeb) return;
        setState(() {
          _error = 'Google sign-in returned no user.';
          _loading = false;
        });
        return;
      }
      // For native flows, decide between consent (new) and dashboard
      // (returning). isFreshGoogleSignIn uses createdAt proximity.
      if (!AuthService.isFreshGoogleSignIn(user)) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboard()),
        );
        return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ConsentCaptureScreen(
            parentId: user.id,
            displayName: AuthService.deriveDisplayName(user),
            email: user.email ?? '',
          ),
        ),
      );
    } on GoogleSignInCancelledException {
      // User dismissed the Google account picker — treat as soft
      // cancel, no error banner.
      if (mounted) setState(() => _loading = false);
    } on GoogleSignInConfigException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSignUp ? 'Create your account' : 'Welcome back';
    final subtitle = _isSignUp
        ? "You're the parent. Kids get their own setup."
        : 'Sign in to keep the streak going.';

    final body = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenPadding,
        vertical: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand mark + wordmark, small, inline. Padding lifts
            // the whole form off the top edge.
            Row(
              children: [
                const BrandLogo.signIn(),
                const SizedBox(width: 10),
                Text('DoneFirst', style: AppText.screenTitle()),
              ],
            ),
            const SizedBox(height: 28),
            Text(title, style: AppText.title(size: 27)),
            const SizedBox(height: 6),
            Text(subtitle, style: AppText.bodySecondary(size: 14)),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              ),
            if (_isSignUp) ...[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(LucideIcons.user, size: 18),
                ),
                textInputAction: TextInputAction.next,
                validator: Validators.name,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'sara@email.com',
                prefixIcon: Icon(LucideIcons.mail, size: 18),
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
                helperText: _isSignUp ? '6+ characters' : null,
                prefixIcon: const Icon(LucideIcons.lock, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? LucideIcons.eyeOff : LucideIcons.eye,
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
            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _resetPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    'Forgot password?',
                    style: AppText.body(color: AppColors.green, size: 13),
                  ),
                ),
              ),
            if (_isSignUp) ...[const SizedBox(height: 16), _buildConsentCard()],
            const SizedBox(height: 20),
            // Primary CTA — full width, chunky kit button.
            DfButton(
              _isSignUp ? 'Create account' : 'Sign in',
              onPressed: (_loading || (_isSignUp && !_signUpReady))
                  ? null
                  : _submit,
              loading: _loading,
            ),
            const SizedBox(height: 18),
            // "Or" divider — peer of the password path, not a
            // footnote.
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR', style: AppText.eyebrow()),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            _buildGoogleButton(),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () => setState(() {
                  _isSignUp = !_isSignUp;
                  _error = null;
                }),
                child: Text(
                  _isSignUp
                      ? 'Already have one? Sign in'
                      : 'New here? Create an account',
                  style: AppText.body(color: AppColors.green, size: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      // Paper background matches the rest of the parent flow.
      backgroundColor: AppColors.paper,
      body: SafeArea(child: body),
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

  /// Google sign-in button, restyled to the kit's outline treatment
  /// (52 height, r16, warm border) with the on-brand "G" tile kept as
  /// the leading glyph so we don't need to fetch the Google SVG asset.
  Widget _buildGoogleButton() {
    final enabled = !_loading;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? _signInWithGoogle : null,
        child: Container(
          width: double.infinity,
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.button),
            border: Border.all(color: AppColors.borderCol, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isSignUp ? 'Sign up with Google' : 'Sign in with Google',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.button(color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Parental consent capture card. The header checkbox mirrors the
  /// approved mock copy ("I'm 18+ and a parent or legal guardian. I
  /// agree to the Terms & Privacy Policy.") and drives the two
  /// attestations it names; the itemized data / AI-verification /
  /// analytics consents and the typed signature stay in the expandable
  /// section below so nothing legally required is granted silently.
  Widget _buildConsentCard() {
    final allChecked = _allRequiredAcks;
    return DfCard(
      padding: EdgeInsets.zero,
      borderColor: allChecked
          ? AppColors.green.withValues(alpha: 0.5)
          : AppColors.borderCol,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _ackAdult && _ackGuardian,
                  onChanged: _loading
                      ? null
                      : (v) => setState(() {
                          _ackAdult = v ?? false;
                          _ackGuardian = v ?? false;
                        }),
                  activeColor: AppColors.green,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: RichText(
                      text: TextSpan(
                        style: AppText.body(size: 13),
                        children: [
                          const TextSpan(
                            text:
                                "I'm 18+ and a parent or legal guardian. "
                                'I agree to the ',
                          ),
                          TextSpan(
                            text: 'Terms',
                            style: AppText.body(
                              size: 13,
                              color: AppColors.green,
                              w: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: ' & '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: AppText.body(
                              size: 13,
                              color: AppColors.green,
                              w: FontWeight.w700,
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _consentExpanded = !_consentExpanded),
                  icon: Icon(
                    _consentExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    color: AppColors.ink45,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: _consentExpanded
                      ? 'Hide full consent details'
                      : 'Show full consent details',
                ),
              ],
            ),
          ),
          if (_consentExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Column(
                children: [
                  _ackTile(
                    value: _ackChildData,
                    onChanged: _loading
                        ? null
                        : (v) => setState(() => _ackChildData = v ?? false),
                    title:
                        "I consent to DoneFirst storing photos of my child's "
                        'homework and basic profile info.',
                    subtitle: 'Photos are stored privately and never shared.',
                  ),
                  _ackTile(
                    value: _ackAiVerification,
                    onChanged: _loading
                        ? null
                        : (v) =>
                              setState(() => _ackAiVerification = v ?? false),
                    title:
                        'I consent to AI proof verification (Mistral) '
                        "reviewing my child's submitted photos.",
                    subtitle:
                        'Verification runs on the first photo and the '
                        'result is shown to you.',
                  ),
                  _ackTile(
                    value: _ackOptionalAnalytics,
                    onChanged: _loading
                        ? null
                        : (v) => setState(
                            () => _ackOptionalAnalytics = v ?? false,
                          ),
                    title:
                        '(Optional) Share anonymous usage stats so we can '
                        'improve DoneFirst.',
                    subtitle:
                        'You can change this anytime in Settings. Off by '
                        'default.',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Type your full legal name as your signature:',
                    style: AppText.body(size: 12, w: FontWeight.w600),
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
                    style: AppText.body(size: 13),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Policy ${ConsentService.currentPolicyVersion}. '
                    'You can view the full policy in Settings after signing '
                    'up.',
                    style: AppText.caption(size: 10.5),
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
      activeColor: AppColors.green,
      title: Text(title, style: AppText.body(size: 12.5, color: AppColors.ink)),
      subtitle: Text(subtitle, style: AppText.caption(size: 10.5)),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      dense: true,
    );
  }
}
