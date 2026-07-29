import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/coparent_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../models/models.dart';

class CoparentScreen extends StatefulWidget {
  const CoparentScreen({super.key});

  @override
  State<CoparentScreen> createState() => _CoparentScreenState();
}

class _CoparentScreenState extends State<CoparentScreen> {
  final _coparentService = CoparentService();
  final _sessionService = SessionService();
  final _emailController = TextEditingController();
  List<ParentInvite> _invites = [];
  List<ParentUser> _coParents = [];
  List<ParentInvite> _myInvites = [];
  bool _loading = true;
  String? _error;
  String? _familyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _familyId = await _sessionService.getOrCreateFamily();
      // Three independent fetches sharing the same _familyId. Run
      // them in parallel so the screen goes from 'family lookup +
      // 3 fetches' to 'family lookup + 1 fetch' worth of latency.
      final results = await Future.wait<Object?>([
        _coparentService.getPendingInvites(_familyId!),
        _coparentService.getCoParents(_familyId!),
        _coparentService.getMyInvites(),
      ]);
      final invites = results[0] as List<ParentInvite>;
      final coParents = results[1] as List<ParentUser>;
      final myInvites = results[2] as List<ParentInvite>;
      if (mounted) {
        setState(() {
          _invites = invites;
          _coParents = coParents;
          _myInvites = myInvites;
        });
      }
    } catch (e) {
      // Surface the failure (mirror of the pending_proofs_screen +
      // schedules_screen fixes). Without this catch the spinner
      // runs forever on a Supabase hiccup.
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _cancelInvite(String id) async {
    try {
      await _coparentService.cancelInvite(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t cancel invite: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _removeCoparent(ParentUser p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Remove ${p.displayName.isNotEmpty ? p.displayName : p.email}?',
        ),
        content: const Text(
          'They\'ll lose access to approve or manage this family.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _coparentService.removeCoparent(p.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t remove co-parent: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
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
      appBar: AppBar(title: const Text('Co-parent')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError(_error!);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        if (_myInvites.isNotEmpty) ...[
          DfSectionLabel('Invitations for you'),
          ..._myInvites.map(
            (inv) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MyInviteCard(
                invite: inv,
                onAccept: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _coparentService.acceptInvite(inv.id);
                    if (!mounted) return;
                    navigator.pushReplacementNamed('/dashboard');
                  } catch (e) {
                    // Without this catch, a Supabase hiccup on
                    // acceptInvite leaves the invite pending with
                    // no feedback — the user taps Accept and
                    // nothing happens.
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Couldn’t accept invite: $e'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                },
                onDecline: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await _coparentService.cancelInvite(inv.id);
                    await _load();
                  } catch (e) {
                    // Same shape as the Accept button: a Supabase
                    // hiccup on cancelInvite would leave the
                    // invite still pending with no feedback.
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Couldn’t decline invite: $e'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        DfSectionLabel('Grown-ups'),
        if (_coParents.isEmpty && _invites.isEmpty)
          DfEmptyState(
            icon: LucideIcons.users,
            title: 'No co-parents yet',
            hint: 'Invite your partner so two of you can approve homework.',
          )
        else ...[
          ..._coParents.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DfCard(
                child: Row(
                  children: [
                    DfAvatar(
                      p.displayName.isNotEmpty ? p.displayName : p.email,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.displayName.isNotEmpty
                                ? p.displayName
                                : 'Unknown',
                            style: AppText.cardHeader(size: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(p.email, style: AppText.caption()),
                        ],
                      ),
                    ),
                    DfStatusPill('Can approve', tone: DfPillTone.success),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.userMinus,
                        size: 18,
                        color: AppColors.dangerFg,
                      ),
                      tooltip: 'Remove co-parent',
                      onPressed: () => _removeCoparent(p),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ..._invites.map(
            (inv) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DfCard(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.amberTint,
                        borderRadius: BorderRadius.circular(AppRadius.iconTile),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.hourglass,
                        size: 18,
                        color: AppColors.amberDeep,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            inv.inviteeEmail,
                            style: AppText.cardHeader(size: 15),
                          ),
                          const SizedBox(height: 2),
                          Text('Invite pending', style: AppText.caption()),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _cancelInvite(inv.id),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        DfSectionLabel('Invite a co-parent'),
        DfCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share approving with your partner — they\'ll see the same '
                'kids, sessions and proofs you do.',
                style: AppText.body(size: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Partner\'s email',
                  prefixIcon: Icon(LucideIcons.mail),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              DfButton(
                'Send invite',
                icon: LucideIcons.send,
                onPressed: _invite,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DfCard(
            color: AppColors.border2,
            borderColor: AppColors.border2,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.borderCol,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 120,
                        color: AppColors.borderCol,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 160,
                        color: AppColors.borderCol,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        const SizedBox(height: 60),
        DfCard(
          child: Column(
            children: [
              const Icon(
                LucideIcons.wifiOff,
                color: AppColors.dangerFg,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                'Couldn\'t load co-parent info',
                style: AppText.cardHeader(size: 16),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body(size: 13),
              ),
              const SizedBox(height: 16),
              DfButton.outline(
                'Try again',
                icon: LucideIcons.refreshCw,
                onPressed: _load,
                expand: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyInviteCard extends StatelessWidget {
  final ParentInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _MyInviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return DfCard(
      borderColor: AppColors.green.withValues(alpha: 0.4),
      color: AppColors.greenTint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.mailPlus,
                color: AppColors.green,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You\'ve been invited!',
                      style: AppText.cardHeader(size: 15),
                    ),
                    const SizedBox(height: 2),
                    Text('Join as a co-parent', style: AppText.caption()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: DfButton('Accept', onPressed: onAccept)),
              const SizedBox(width: 10),
              Expanded(
                child: DfButton.outline('Decline', onPressed: onDecline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
