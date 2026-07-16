import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/pin_guard.dart';
import 'upgrade_screen.dart';
import 'coparent_screen.dart';
import 'help_screen.dart';
import 'kid_device_pairing_screen.dart';

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
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Profile updated')));
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
    await _parentPrefs.setPin(pin1);
    if (!mounted) return;
    setState(() => _pin = pin1);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN saved')),
    );
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
            decoration: InputDecoration(
              counterText: '',
              labelText: label,
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmController = TextEditingController();
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
              decoration: const InputDecoration(labelText: 'Current password'),
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
    if (result == true) {
      final newPass = newPasswordController.text.trim();
      final confirm = confirmController.text.trim();
      if (newPass.length < 6) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password must be at least 6 characters'),
            ),
          );
        }
        return;
      }
      if (newPass != confirm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passwords do not match')),
          );
        }
        return;
      }
      try {
        await _auth.changePassword(newPass);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully')),
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
    // Dialog controllers are local-scope; dispose on every exit
    // path (save, cancel, validation failure, server error).
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmController.dispose();
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
                        icon: const Icon(Icons.copy),
                        tooltip: 'Copy JSON',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: json),
                          );
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Export copied to clipboard'),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
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
                        color: Theme.of(ctx)
                            .colorScheme
                            .surfaceContainerHighest,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
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
    confirmController.dispose();
    // Snapshot the password before disposing — reading .text from a
    // disposed TextEditingController is undefined per the contract,
    // and even though today's implementation happens to return the
    // last value, we'd rather not depend on that.
    final password = passwordController.text;
    passwordController.dispose();
    if (confirmed != true) return;
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
      if (mounted)
        Navigator.pushNamedAndRemoveUntil(context, '/auth', (_) => false);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  /// Sign the user in with their email + password so the access token
  /// is fresh before invoking the destructive Edge Function. We don't
  /// keep the user signed in afterwards — _auth.deleteAccount() ends
  /// with signOut() anyway.
  Future<void> _supabaseReauthForDelete(
    String email,
    String password,
  ) async {
    await _auth.verifyPassword(email, password);
  }

  /// Resend the Supabase signup confirmation email. Used when the
  /// email didn't arrive (spam, typo before they edited the to-field,
  /// mail provider delay).
  Future<void> _resendVerification() async {
    final email = _userEmail;
    if (email == null) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No email on file.')));
      return;
    }
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.email,
        email: email,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification email re-sent to $email.'),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  /// Copy a pre-formatted support address to the clipboard. We don't
  /// ship a separate in-app helpdesk yet — at this stage the launch
  /// team handles feedback by hand. Adding url_launcher for a mailto:
  /// isn't worth the extra dep for one screen.
  Future<void> _reportProblem() async {
    const supportEmail = 'support@donefirst.app';
    await Clipboard.setData(
      const ClipboardData(text: supportEmail),
    );
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('support@donefirst.app copied. Email us there.'),
        ),
      );
  }

  /// True for trivially-guessable 4-digit PINs. We reject two
  /// shapes — all-same digits (0000, 1111, …) and 4-in-a-row
  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section('Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha:0.1),
                    child: Text(
                      _displayName?.substring(0, 1).toUpperCase() ?? '?',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(_displayName ?? 'Unknown'),
                  subtitle: Text(_userEmail ?? ''),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _editProfile,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('DoneFirst Plus'),
                  subtitle: const Text(
                    '${UpgradeScreen.freeLimit} free sessions/month',
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UpgradeScreen()),
                    ),
                    child: const Text('Upgrade'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Co-Parent'),
                  subtitle: const Text('Invite a partner to manage together'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => PinGuard.push(
                    context,
                    destination: const CoparentScreen(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: const Text('Kid devices'),
                  subtitle: const Text(
                    'Pair or revoke the device running your kid’s mode',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => PinGuard.push(
                    context,
                    destination: const KidDevicePairingScreen(),
                    title: 'Manage kid devices',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(
                    _pin == null ? 'Set Parent PIN' : 'Change Parent PIN',
                  ),
                  subtitle: Text(
                    _pin == null
                        ? 'Protect parent screens with PIN'
                        : 'PIN is set',
                  ),
                  trailing: _pin == null
                      ? const Icon(Icons.arrow_forward_ios, size: 16)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.danger,
                                size: 20,
                              ),
                              tooltip: 'Remove PIN',
                              onPressed: () async {
                                await _parentPrefs.setPin(null);
                                if (!mounted) return;
                                setState(() => _pin = null);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PIN removed')),
                                );
                              },
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                  onTap: _setPin,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Change Password'),
                  subtitle: const Text('Update your login password'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _changePassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _section('Notifications'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Proof submitted'),
                  subtitle: const Text(
                    'When your child submits homework photo',
                  ),
                  value: _notifyProofSubmitted,
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
                  onChanged: (v) async {
                    setState(() => _notifySessionComplete = v);
                    await _notificationPrefs.setEnabled(
                      NotificationPreferencesService.typeSessionComplete,
                      v,
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _section('Appearance'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('Dark Mode'),
              value: darkModeNotifier.value,
              onChanged: (v) => setState(() => darkModeNotifier.value = v),
            ),
          ),
          const SizedBox(height: 24),
          _section('Proof Verification'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Auto-approve math proofs'),
                  subtitle: const Text(
                    'Skip approval when Mistral AI detects math homework',
                  ),
                  value: _autoApproveMath,
                  onChanged: (v) async {
                    setState(() => _autoApproveMath = v);
                    await _parentPrefs.setAutoApproveMath(v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _section('Default Session'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Default duration',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
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
          ),
          const SizedBox(height: 32),
          _section('Your Data'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('Export My Data'),
              subtitle: const Text(
                'Download a JSON copy of your profile, family, sessions, '
                'proofs, and consent records.',
              ),
              trailing: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _exporting ? null : _exportData,
            ),
          ),
          const SizedBox(height: 32),
          _section('Consent Audit'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Consent records are an immutable audit trail of every '
                    'parental attestation you have made. They are required '
                    'by COPPA and GDPR-K.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingConsent)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (_consentHistory.isEmpty)
                    const Text(
                      'No consent records yet.',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    )
                  else
                    ...(_consentHistory.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 16, color: AppColors.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.displayType,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    '${c.consentVersion} • ${c.createdAt.toLocal().toString().split('.').first}',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
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
          ),
          const SizedBox(height: 32),
          _section('Legal'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  subtitle: const Text(
                    'What we collect and how we use it',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPolicyDialog(
                    context,
                    'Privacy Policy',
                    kPrivacyPolicyText,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  subtitle: const Text('Rules for using DoneFirst'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showPolicyDialog(
                    context,
                    'Terms of Service',
                    kTermsOfServiceText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _section('Danger Zone'),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.delete_forever,
                color: AppColors.danger,
              ),
              title: Text(
                'Delete Account',
                style: TextStyle(color: AppColors.danger),
              ),
              subtitle: const Text('Permanently delete all data'),
              onTap: _deleteAccount,
            ),
          ),
          const SizedBox(height: 32),
          _section('About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Help & Support'),
                  subtitle: const Text(
                    'FAQ and troubleshooting tips',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HelpScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('App version'),
                  subtitle: Text(
                    'DoneFirst $_appVersion',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Resend verification email'),
                  subtitle: const Text(
                    "Didn't get the confirmation email? Send it again.",
                  ),
                  onTap: _resendVerification,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Report a problem'),
                  subtitle: const Text(
                    'Copies our support email so you can write us.',
                  ),
                  onTap: _reportProblem,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
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
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      body,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
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
  }
}
