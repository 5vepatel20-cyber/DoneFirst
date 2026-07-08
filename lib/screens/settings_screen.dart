import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_mode.dart';
import '../utils/policy_text.dart';
import 'upgrade_screen.dart';
import 'coparent_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _profileService = ProfileService();
  bool _notifyProofSubmitted = true;
  bool _notifyBreakRequested = true;
  bool _notifySessionComplete = true;
  bool _autoApproveMath = false;
  int _defaultMinutes = 60;
  bool _loading = true;
  String? _userEmail;
  String? _pin;

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
      final profile = await _profileService.getParentProfile();
      final familyName = await _profileService.getFamilyName();
      setState(() {
        _userEmail = user.email;
        _displayName = profile?.displayName ?? user.email;
        _familyName = familyName ?? 'My Family';
        _loading = false;
      });
    }
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _displayName);
    final familyController = TextEditingController(text: _familyName);
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
  }

  Future<void> _setPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_pin == null ? 'Set PIN' : 'Change PIN'),
        content: TextField(
          controller: controller,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            labelText: '4-digit PIN',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (pin != null && pin.length == 4) {
      setState(() => _pin = pin);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PIN saved')));
    }
  }

  Future<void> _changePassword() async {
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
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'All your data will be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _auth.deleteAccount();
        if (mounted)
          Navigator.pushNamedAndRemoveUntil(context, '/auth', (_) => false);
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

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
                    backgroundColor: AppColors.primary.withOpacity(0.1),
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CoparentScreen()),
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
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
                  onChanged: (v) => setState(() => _notifyProofSubmitted = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Break requested'),
                  subtitle: const Text('When your child asks for a break'),
                  value: _notifyBreakRequested,
                  onChanged: (v) => setState(() => _notifyBreakRequested = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Session complete'),
                  subtitle: const Text('When all tasks are done'),
                  value: _notifySessionComplete,
                  onChanged: (v) => setState(() => _notifySessionComplete = v),
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
                  onChanged: (v) => setState(() => _autoApproveMath = v),
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
                    onSelectionChanged: (v) =>
                        setState(() => _defaultMinutes = v.first),
                  ),
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
