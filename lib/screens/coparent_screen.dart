import 'package:flutter/material.dart';
import '../services/coparent_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

class CoparentScreen extends StatefulWidget {
  const CoparentScreen({super.key});

  @override
  State<CoparentScreen> createState() => _CoparentScreenState();
}

class _CoparentScreenState extends State<CoparentScreen> {
  final _coparentService = CoparentService();
  final _sessionService = SessionService();
  final _emailController = TextEditingController();
  List<Map<String, dynamic>> _invites = [];
  List<Map<String, dynamic>> _coParents = [];
  List<Map<String, dynamic>> _myInvites = [];
  bool _loading = true;
  String? _familyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _familyId = await _sessionService.getOrCreateFamily();
    final invites = await _coparentService.getPendingInvites(_familyId!);
    final coParents = await _coparentService.getCoParents(_familyId!);
    final myInvites = await _coparentService.getMyInvites();
    if (mounted)
      setState(() {
        _invites = invites;
        _coParents = coParents;
        _myInvites = myInvites;
        _loading = false;
      });
  }

  Future<void> _invite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _familyId == null) return;
    try {
      await _coparentService.invite(familyId: _familyId!, email: email);
      _emailController.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invite sent to $email')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Co-Parent')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_myInvites.isNotEmpty) ...[
                  _section('Pending Invitations for You'),
                  ..._myInvites.map(
                    (inv) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.mail_outline,
                          color: AppColors.accent,
                        ),
                        title: const Text('You\'ve been invited!'),
                        subtitle: Text('Join as co-parent'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton(
                              onPressed: () async {
                                await _coparentService.acceptInvite(inv['id']);
                                if (mounted)
                                  Navigator.pushReplacementNamed(
                                    context,
                                    '/dashboard',
                                  );
                              },
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 4),
                            TextButton(
                              onPressed: () async {
                                await _coparentService.cancelInvite(inv['id']);
                                await _load();
                              },
                              child: const Text('Decline'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _section('Current Co-Parents'),
                if (_coParents.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'No co-parents yet',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._coParents.map(
                    (p) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.success.withOpacity(0.1),
                          child: Text(
                            (p['display_name'] as String? ?? '?')[0]
                                .toUpperCase(),
                            style: TextStyle(color: AppColors.success),
                          ),
                        ),
                        title: Text(p['display_name'] as String? ?? 'Unknown'),
                        subtitle: Text(p['email'] as String? ?? ''),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                _section('Invite a Co-Parent'),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Share management with your partner',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Partner\'s email',
                                  prefixIcon: Icon(Icons.email),
                                ),
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _invite,
                              child: const Text('Send Invite'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_invites.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _section('Pending Invites'),
                  ..._invites.map(
                    (inv) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(
                          Icons.hourglass_empty,
                          color: AppColors.accent,
                        ),
                        title: Text(inv['invitee_email'] as String? ?? ''),
                        subtitle: const Text('Pending'),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.danger,
                          ),
                          onPressed: () async {
                            await _coparentService.cancelInvite(inv['id']);
                            await _load();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
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
}
