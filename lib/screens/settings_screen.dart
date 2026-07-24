import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/consent_service.dart';
import '../services/data_export_service.dart';
import '../services/profile_service.dart';
import '../services/parent_preferences_service.dart';
import '../models/parent_user.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode.dart';
import '../utils/policy_text.dart';
import '../utils/pin_strength.dart';
import '../services/notification_preferences_service.dart';
import '../widgets/monogram_avatar.dart';
import '../widgets/pin_guard.dart';
import '../widgets/df_kit.dart';
import 'upgrade_screen.dart';
import 'coparent_screen.dart';
import 'help_screen.dart';
import 'kid_device_pairing_screen.dart';
import 'device_permissions_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _profileService = ProfileService();
  final _consentService = ConsentService();
  final _exportService = DataExportService();
  final _notificationPrefs = NotificationPreferencesService();
  final _parentPrefs = ParentPreferencesService();
  static const String _appVersion = '1.0.0';
  bool _notifyProofSubmitted = true;
  bool _notifyBreakRequested = true;
  bool _notifySessionComplete = true;
  bool _autoApproveMath = false;
  int _defaultMinutes = ParentPreferencesService.defaultMinutes;
  bool _loading = true;
  String? _userEmail;
  String? _pin;
  List<ConsentRecord> _consentHistory = [];
  bool _loadingConsent = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _displayName;
  String? _familyName;

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // Parent profile + family name are independent reads — both
      // are needed for the header, both feed the same setState below.
      // Run them in parallel so the header doesn't take 2× the
      // round-trip latency.
      final profileResults = await Future.wait<Object?>([
        _profileService.getParentProfile(),
        _profileService.getFamilyName(),
      ]);
      final profile = profileResults[0] as ParentUser?;
      final familyName = profileResults[1] as String?;
      setState(() {
        _userEmail = user.email;
        _displayName = profile?.displayName ?? user.email;
        _familyName = familyName ?? 'My Family';
        _loading = false;
      });
      // Load consent history in the background; non-fatal if it fails.
      setState(() => _loadingConsent = true);
      try {
        final history = await _consentService.getConsentHistory(user.id);
        if (mounted) setState(() => _consentHistory = history);
      } catch (_) {
        // Parental_consent table may not exist yet (migration 9 not run).
        // Render empty list silently — the Audit section won't show rows.
      } finally {
        if (mounted) setState(() => _loadingConsent = false);
      }
      // Notification prefs are stored locally; reading SharedPreferences
      // is fast but we still do it off the load path.
      final notifPrefs = await _notificationPrefs.getPrefs();
      // Read the three parent prefs (PIN, autoApproveMath, default
      // duration) in parallel — three independent SharedPreferences
      // lookups that have no inter-dependencies.
      final parentPrefsResults = await Future.wait([
        _parentPrefs.getPin(),
        _parentPrefs.getAutoApproveMath(),
        _parentPrefs.getDefaultMinutes(),
      ]);
      if (mounted) {
        setState(() {
          _notifyProofSubmitted =
              notifPrefs[NotificationPreferencesService.typeProofSubmitted] ??
              true;
          _notifyBreakRequested =
              notifPrefs[NotificationPreferencesService.typeBreakRequested] ??
              true;
          _notifySessionComplete =
              notifPrefs[NotificationPreferencesService.typeSessionComplete] ??
              true;
          _pin = parentPrefsResults[0] as String?;
          _autoApproveMath = parentPrefsResults[1] as bool;
          _defaultMinutes = parentPrefsResults[2] as int;
        });
      }
    }
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _displayName);
    final familyController = TextEditingController(text: _familyName);
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Edit Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Your Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: familyController,
                decoration: const InputDecoration(labelText: 'Family Name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (result == true) {
        final newName = nameController.text.trim();
        final newFamily = familyController.text.trim();
        // Snapshot the controller text BEFORE awaiting, so a
        // throw mid-updateName never strands us with a possibly
        // disposed controller to read .text on. If the awaited
        // call throws we rethrow from inside the try, the
        // finally disposes both controllers, and the outer call
        // site shows a snackbar. Same pattern as _deleteAccount.
        if (newName.isNotEmpty && newName != _displayName) {
          await _profileService.updateParentName(newName);
          setState(() => _displayName = newName);
        }
        if (newFamily.isNotEmpty && newFamily != _familyName) {
          await _profileService.updateFamilyName(newFamily);
          setState(() => _familyName = newFamily);
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        }
      }
    } finally {
      // Dialog controllers are local-scope; release their listeners
      // on every dialog exit path (save, cancel, validation
      // short-circuit, OR a thrown updateParentName / updateFamily-
      // Name). Saves over a long session otherwise leak two
      // controllers per edit.
      nameController.dispose();
      familyController.dispose();
    }
  }

  Future<void> _setPin() async {
    // Two-step confirm: enter PIN, then re-enter. Without the
    // confirm step, a single-field typo would silently save a
    // wrong PIN and lock the parent out of every gated action in
    // the app next time they tap one.
    final pin1 = await _showPinEntryDialog(
      title: _pin == null ? 'Set PIN' : 'Change PIN',
      label: 'New 4-digit PIN',
      primaryLabel: 'Next',
    );
    if (pin1 == null) return;
    final pin1Reason = pinRejectionReason(pin1);
    if (pin1Reason != null) {
      _showPinSnackBar(pin1Reason);
      return;
    }
    final pin2 = await _showPinEntryDialog(
      title: 'Confirm PIN',
      label: 'Re-enter PIN',
      primaryLabel: 'Save',
    );
    if (pin2 == null) return;
    if (pin2 != pin1) {
      _showPinSnackBar('PINs didn’t match — try again.');
      return;
    }
    try {
      await _parentPrefs.setPin(pin1);
    } catch (e) {
      // Without this catch, a SharedPreferences write failure makes
      // the parent think the new PIN was saved (the snackbar says
      // "PIN saved") but the old PIN is still on file. They'd be
      // locked out at the next gated action. Same risk shape as
      // forgot_pin_flow.run — always surface the failure.
      _showPinSnackBar('Couldn’t save PIN: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _pin = pin1);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('PIN saved')));
  }

  /// Shared PIN-entry dialog used by both the "enter new PIN"
  /// and "confirm PIN" steps of _setPin. Returns the entered
  /// digits or null on cancel. The TextEditingController is
  /// created locally so the dialog is self-contained — no
  /// caller-side state to leak between invocations.
  Future<String?> _showPinEntryDialog({
    required String title,
    required String label,
    required String primaryLabel,
  }) async {
    // Hoist the controller out of the builder so we can dispose
    // it after the dialog pops. Previously it lived inside the
    // builder closure, which meant one leaked controller per
    // PIN entry (Set/Change/Confirm flows). Each PIN setup hits
    // this dialog twice in a row, so the leak doubled.
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: InputDecoration(counterText: '', labelText: label),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(primaryLabel),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  void _showPinSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changePassword() async {
    // Changing the password from a kid's session would lock the
    // parent out of their own account. Require the parent PIN
    // before letting this action run.
    final pinOk = await PinGuard.confirmInline(
      context,
      actionLabel: 'Continue',
    );
    if (!pinOk) return;
    if (!mounted) return;
    // Capture messenger + controllers NOW so the awaits below don't
    // need to re-touch BuildContext for ScaffoldMessenger.of(). The
    // controllers need try/finally to dispose exactly once even on
    // the early-return paths.
    final messenger = ScaffoldMessenger.of(context);
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Update'),
            ),
          ],
        ),
      );
      if (result != true) return;
      if (!mounted) return;
      final newPass = newPasswordController.text.trim();
      final confirm = confirmController.text.trim();
      if (newPass.length < 6) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Password must be at least 6 characters'),
          ),
        );
        return;
      }
      if (newPass != confirm) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Passwords do not match')),
        );
        return;
      }
      try {
        await _auth.changePassword(newPass);
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Password updated successfully')),
        );
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      currentPasswordController.dispose();
      newPasswordController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _exportData() async {
    // Export contains kids' names, schedules, all sessions, and
    // consent records — gate it the same way as Delete Account.
    final pinOk = await PinGuard.confirmInline(
      context,
      actionLabel: 'Continue',
    );
    if (!pinOk) return;
    setState(() => _exporting = true);
    try {
      final json = await _exportService.exportAsJsonString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                          'Your Data Export',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.copy, size: 20),
                        tooltip: 'Copy JSON',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: json));
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Export copied to clipboard'),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Export version ${DataExportService.exportVersion} • '
                    '${json.length} characters',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          ctx,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: SelectableText(
                            json,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteAccount() async {
    // PIN gate before showing the destructive dialog. If a parent
    // PIN is set, require it before Delete Account is even
    // reachable — typing "DELETE" + a password together is still
    // vulnerable to a kid with the password memorized.
    final pinOk = await PinGuard.confirmInline(
      context,
      actionLabel: 'Continue',
    );
    if (!pinOk) return;
    if (!mounted) return;
    // Capture handles + controllers so the post-await branches don't
    // touch BuildContext again — eliminates use_build_context_synchronously.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var matches = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Delete Account?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All your data will be permanently deleted — including '
                  'your children, sessions, proofs, schedules, presets, '
                  'and consent records. This cannot be undone.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Type DELETE to confirm:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'DELETE',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final ok = v.trim() == 'DELETE';
                    if (ok != matches) {
                      setLocal(() => matches = ok);
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Enter your password:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: matches && passwordController.text.isNotEmpty
                    ? () => Navigator.pop(ctx, true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                child: const Text('Delete Forever'),
              ),
            ],
          ),
        );
      },
    );
    // Snapshot the password before disposing — reading .text from a
    // disposed TextEditingController is undefined per the contract,
    // and even though today's implementation happens to return the
    // last value, we'd rather not depend on that.
    final password = passwordController.text;
    confirmController.dispose();
    passwordController.dispose();
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      // Re-authenticate the user with the password they just typed.
      // Supabase considers the access token expired if it's been a while
      // since the user last used the app, and a stale token would make
      // the delete-account Edge Function reject the call. Re-sign-in
      // guarantees a fresh token.
      final email = _userEmail;
      if (email == null) {
        throw StateError('No current user — cannot re-authenticate.');
      }
      await _supabaseReauthForDelete(email, password);
      await _auth.deleteAccount();
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  /// Sign the user in with their email + password so the access token
  /// is fresh before invoking the destructive Edge Function. We don't
  /// keep the user signed in afterwards — _auth.deleteAccount() ends
  /// with signOut() anyway.
  Future<void> _supabaseReauthForDelete(String email, String password) async {
    await _auth.verifyPassword(email, password);
  }

  /// Sign out and return to the auth screen. Mirrors the destructive
  /// flow's navigation (pushNamedAndRemoveUntil '/auth') so the back
  /// stack is cleared and a kid can't swipe back into the parent app.
  Future<void> _signOut() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _auth.signOut();
      if (!mounted) return;
      navigator.pushNamedAndRemoveUntil('/auth', (_) => false);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
    }
  }

  /// Resend the Supabase signup confirmation email. Used when the
  /// email didn't arrive (spam, typo before they edited the to-field,
  /// mail provider delay).
  Future<void> _resendVerification() async {
    final email = _userEmail;
    if (email == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No email on file.')));
      }
      return;
    }
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.email,
        email: email,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification email re-sent to $email.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  /// Copy a pre-formatted support address to the clipboard. We don't
  /// ship a separate in-app helpdesk yet — at this stage the launch
  /// team handles feedback by hand. Adding url_launcher for a mailto:
  /// isn't worth the extra dep for one screen.
  Future<void> _reportProblem() async {
    const supportEmail = 'support@donefirst.app';
    await Clipboard.setData(const ClipboardData(text: supportEmail));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('support@donefirst.app copied. Email us there.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(title: Text('Settings', style: AppText.screenTitle())),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            _skeletonBlock(height: 84),
            const SizedBox(height: 14),
            _skeletonBlock(height: 64),
            const SizedBox(height: 22),
            _skeletonBlock(height: 180),
            const SizedBox(height: 22),
            _skeletonBlock(height: 140),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: Text('Settings', style: AppText.screenTitle())),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          // ── Profile ───────────────────────────────────────────────
          DfCard(
            onTap: _editProfile,
            child: Row(
              children: [
                MonogramAvatar.parent(name: _displayName ?? '', size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName ?? 'Unknown',
                        style: AppText.cardHeader(size: 18),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _userEmail ?? '',
                        style: AppText.bodySecondary(size: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppColors.ink45,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Plan ──────────────────────────────────────────────────
          DfCard(
            color: AppColors.ink,
            borderColor: AppColors.ink,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.iconTile),
                  ),
                  child: const Icon(
                    LucideIcons.sparkles,
                    size: 20,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DoneFirst Free',
                        style: AppText.cardHeader(
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${UpgradeScreen.freeLimit} free sessions this month',
                        style: AppText.bodySecondary(
                          size: 12,
                          color: const Color(0xFFCFC7B8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                DfButton.amber(
                  'Upgrade',
                  expand: false,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // ── Controls ──────────────────────────────────────────────
          const DfSectionLabel('Controls'),
          _group([
            SwitchListTile(
              title: const Text('Proof submitted'),
              subtitle: const Text('When your child submits homework photo'),
              value: _notifyProofSubmitted,
              activeThumbColor: AppColors.green,
              onChanged: (v) async {
                setState(() => _notifyProofSubmitted = v);
                await _notificationPrefs.setEnabled(
                  NotificationPreferencesService.typeProofSubmitted,
                  v,
                );
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Break requested'),
              subtitle: const Text('When your child asks for a break'),
              value: _notifyBreakRequested,
              activeThumbColor: AppColors.green,
              onChanged: (v) async {
                setState(() => _notifyBreakRequested = v);
                await _notificationPrefs.setEnabled(
                  NotificationPreferencesService.typeBreakRequested,
                  v,
                );
              },
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Session complete'),
              subtitle: const Text('When all tasks are done'),
              value: _notifySessionComplete,
              activeThumbColor: AppColors.green,
              onChanged: (v) async {
                setState(() => _notifySessionComplete = v);
                await _notificationPrefs.setEnabled(
                  NotificationPreferencesService.typeSessionComplete,
                  v,
                );
              },
            ),
          ]),
          const SizedBox(height: 14),
          _group([
            SwitchListTile(
              secondary: const Icon(LucideIcons.moon, size: 22),
              title: const Text('Dark Mode'),
              value: darkModeNotifier.value,
              activeThumbColor: AppColors.green,
              onChanged: (v) => setState(() => darkModeNotifier.value = v),
            ),
          ]),
          const SizedBox(height: 14),
          _group([
            SwitchListTile(
              secondary: const Icon(LucideIcons.sparkles, size: 22),
              title: const Text('Approval mode · AI + you'),
              subtitle: const Text(
                'Auto-approve when the AI is highly confident (≥80%) the '
                'photo is real homework. Anything unsure still waits for you.',
              ),
              value: _autoApproveMath,
              activeThumbColor: AppColors.green,
              onChanged: (v) async {
                setState(() => _autoApproveMath = v);
                await _parentPrefs.setAutoApproveMath(v);
              },
            ),
          ]),
          const SizedBox(height: 14),
          DfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Default session length',
                  style: AppText.cardHeader(size: 15),
                ),
                const SizedBox(height: 12),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30 min')),
                    ButtonSegment(value: 60, label: Text('1 hour')),
                    ButtonSegment(value: 90, label: Text('1.5 hr')),
                    ButtonSegment(value: 120, label: Text('2 hr')),
                  ],
                  selected: {_defaultMinutes},
                  onSelectionChanged: (v) async {
                    setState(() => _defaultMinutes = v.first);
                    await _parentPrefs.setDefaultMinutes(v.first);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _group([
            ListTile(
              leading: const Icon(LucideIcons.smartphone, size: 22),
              title: const Text('Kid devices'),
              subtitle: const Text(
                'Pair or revoke the device running your kid’s mode',
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () => PinGuard.push(
                context,
                destination: const KidDevicePairingScreen(),
                title: 'Manage kid devices',
              ),
            ),
            const Divider(height: 1),
            ListTile(
              // Manual re-check entry point for parents whose
              // blocking stopped working mid-session (e.g. an OS
              // update revoked the toggle).
              leading: const Icon(LucideIcons.shieldCheck, size: 22),
              title: const Text('Device permissions'),
              subtitle: const Text(
                'Re-check Usage access and Display over other apps',
              ),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DevicePermissionsScreen(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 26),

          // ── Account ───────────────────────────────────────────────
          const DfSectionLabel('Account'),
          _group([
            ListTile(
              leading: const Icon(LucideIcons.users, size: 22),
              title: const Text('Co-parent'),
              subtitle: const Text('Invite a partner to approve together'),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () =>
                  PinGuard.push(context, destination: const CoparentScreen()),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.lock, size: 22),
              title: Text(
                _pin == null ? 'Set Parent PIN' : 'Change Parent PIN',
              ),
              subtitle: Text(
                _pin == null
                    ? 'Protect parent screens with a PIN'
                    : 'PIN is set',
              ),
              trailing: _pin == null
                  ? const Icon(LucideIcons.chevronRight, size: 16)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            LucideIcons.trash2,
                            color: AppColors.danger,
                            size: 18,
                          ),
                          tooltip: 'Remove PIN',
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await _parentPrefs.setPin(null);
                            if (!mounted) return;
                            setState(() => _pin = null);
                            messenger.showSnackBar(
                              const SnackBar(content: Text('PIN removed')),
                            );
                          },
                        ),
                        const Icon(LucideIcons.chevronRight, size: 16),
                      ],
                    ),
              onTap: _setPin,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.key, size: 22),
              title: const Text('Change password'),
              subtitle: const Text('Update your login password'),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: _changePassword,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.download, size: 22),
              title: const Text('Export my data'),
              subtitle: const Text(
                'A JSON copy of your profile, family, sessions, proofs and '
                'consent records.',
              ),
              trailing: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.chevronRight, size: 16),
              onTap: _exporting ? null : _exportData,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.helpCircle, size: 22),
              title: const Text('Help & support'),
              subtitle: const Text('FAQ and troubleshooting tips'),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                LucideIcons.logOut,
                size: 22,
                color: AppColors.danger,
              ),
              title: Text(
                'Sign out',
                style: AppText.body(
                  color: AppColors.danger,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: _signOut,
            ),
          ]),
          const SizedBox(height: 26),

          // ── Legal & audit ─────────────────────────────────────────
          const DfSectionLabel('Legal'),
          _group([
            ListTile(
              leading: const Icon(LucideIcons.shield, size: 22),
              title: const Text('Privacy Policy'),
              subtitle: const Text('What we collect and how we use it'),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () => _showPolicyDialog(
                context,
                'Privacy Policy',
                kPrivacyPolicyText,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.fileText, size: 22),
              title: const Text('Terms of Service'),
              subtitle: const Text('Rules for using DoneFirst'),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: () => _showPolicyDialog(
                context,
                'Terms of Service',
                kTermsOfServiceText,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          DfCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Consent audit', style: AppText.cardHeader(size: 15)),
                const SizedBox(height: 8),
                Text(
                  'An immutable audit trail of every parental attestation you '
                  'have made. Required by COPPA and GDPR-K.',
                  style: AppText.bodySecondary(size: 12),
                ),
                const SizedBox(height: 12),
                if (_loadingConsent)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else if (_consentHistory.isEmpty)
                  Text(
                    'No consent records yet.',
                    style: AppText.bodySecondary(size: 13),
                  )
                else
                  ...(_consentHistory.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            LucideIcons.checkCircle2,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.displayType,
                                  style: AppText.body(
                                    size: 13,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  '${c.consentVersion} • ${c.createdAt.toLocal().toString().split('.').first}',
                                  style: AppText.caption(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // ── Danger ────────────────────────────────────────────────
          const DfSectionLabel('Danger zone'),
          _group([
            ListTile(
              leading: const Icon(
                LucideIcons.trash2,
                color: AppColors.danger,
                size: 22,
              ),
              title: Text(
                'Delete account',
                style: AppText.body(
                  color: AppColors.danger,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Permanently delete all data'),
              onTap: _deleteAccount,
            ),
          ]),
          const SizedBox(height: 26),

          // ── About ─────────────────────────────────────────────────
          const DfSectionLabel('About'),
          _group([
            ListTile(
              leading: const Icon(LucideIcons.mail, size: 22),
              title: const Text('Resend verification email'),
              subtitle: const Text(
                "Didn't get the confirmation email? Send it again.",
              ),
              onTap: _resendVerification,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(LucideIcons.bug, size: 22),
              title: const Text('Report a problem'),
              subtitle: const Text(
                'Copies our support email so you can write us.',
              ),
              onTap: _reportProblem,
            ),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Text('DoneFirst v$_appVersion', style: AppText.label()),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Wraps a list of tiles in a padding-less warm card so the grouped
  /// [ListTile]s / [SwitchListTile]s keep their own internal padding
  /// and the dividers run edge-to-edge.
  Widget _group(List<Widget> children) {
    return DfCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(children: children),
      ),
    );
  }

  Widget _skeletonBlock({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.borderCol),
      ),
    );
  }

  void _showPolicyDialog(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
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
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      body,
                      style: const TextStyle(fontSize: 14, height: 1.5),
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
}
