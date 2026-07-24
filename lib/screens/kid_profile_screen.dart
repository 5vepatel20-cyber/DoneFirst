import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/models.dart';
import '../services/kid_device_service.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/destructive_confirm_dialog.dart';

final List<Color> kidColors = [
  AppColors.primary,
  AppColors.accent,
  AppColors.success,
  AppColors.info,
  AppColors.danger,
  AppColors.warning,
  const Color(0xFFE91E63),
  const Color(0xFF00BCD4),
];

const List<String> kidEmojis = [
  '🧑',
  '👧',
  '👦',
  '🧒',
  '👩',
  '👨',
  '🧑‍🎓',
  '🌟',
];

class KidProfileScreen extends StatefulWidget {
  final Child child;

  const KidProfileScreen({super.key, required this.child});

  @override
  State<KidProfileScreen> createState() => _KidProfileScreenState();
}

class _KidProfileScreenState extends State<KidProfileScreen> {
  final _sessionService = SessionService();
  final _kidDeviceService = KidDeviceService();
  late TextEditingController _nameController;
  int _selectedColor = 0;
  int _selectedEmoji = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.child.name);
    if (widget.child.color != null) {
      // The color comes back as a base-16 string ("aabbccdd"-style
      // without the 0x prefix) — int.parse defaults to base-10 so
      // we need to pass radix: 16 explicitly.
      final parsed = int.tryParse(widget.child.color!, radix: 16);
      if (parsed != null) {
        final idx = kidColors.indexWhere(
          (c) => c.toARGB32() == Color(parsed).toARGB32(),
        );
        if (idx >= 0) _selectedColor = idx;
      }
    }
    if (widget.child.emoji != null) {
      final idx = kidEmojis.indexOf(widget.child.emoji!);
      if (idx >= 0) _selectedEmoji = idx;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = _nameController.text.trim();
      if (name.isNotEmpty && name != widget.child.name) {
        await _sessionService.renameChild(widget.child.id, name);
      }
      await _sessionService.updateChildProfile(
        widget.child.id,
        color: kidColors[_selectedColor].toARGB32().toRadixString(16),
        emoji: kidEmojis[_selectedEmoji],
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteChild() async {
    final navigator = Navigator.of(context);
    final child = widget.child;
    // Same warning shape as parent_dashboard._deleteChild — pull
    // paired-device count first so we can show "you're also about to
    // unpair a device" before the type-to-confirm gate.
    int pairedDevices = 0;
    String? firstDeviceName;
    try {
      final devices = await _kidDeviceService.listDevicesForChild(child.id);
      final active = devices.where((d) => !d.isRevoked).toList();
      pairedDevices = active.length;
      firstDeviceName = active.isEmpty ? null : active.first.deviceName;
    } catch (_) {}
    if (!mounted) return;

    final warningText = pairedDevices == 0
        ? null
        : pairedDevices == 1
        ? '${child.name}\'s paired device (${firstDeviceName ?? "unlabeled"}) '
              'will be unpaired. The kid will need to re-pair on their phone.'
        : '${child.name} has $pairedDevices paired devices. All of them '
              'will be unpaired — the kid will need to re-pair each device.';

    // Capture messenger BEFORE the destructive dialog so the catch
    // block below can show a snackbar without tripping
    // use_build_context_synchronously (we'd otherwise be reading
    // `context` after a real network round-trip on the dialog).
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: 'Delete ${child.name}?',
      description:
          'This will permanently remove ${child.name}\'s:\n'
          '  • Homework sessions and proofs\n'
          '  • Tasks and proof images\n'
          '  • Recurring schedules\n'
          '  • Session stats and streak history\n\n'
          'This cannot be undone.',
      confirmPhrase: child.name,
      confirmButtonLabel: 'Delete forever',
      warningText: warningText,
    );
    if (!confirmed) return;
    try {
      await _sessionService.deleteChild(child.id);
    } catch (e) {
      // Without this catch, a Supabase hiccup on deleteChild closes
      // the dialog cleanly but leaves the kid row in the DB and the
      // parent's next refresh shows them still listed. Surface the
      // error so they can retry.
      messenger.showSnackBar(
        SnackBar(
          content: Text('Couldn’t delete ${child.name}: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    if (!mounted) return;
    // Pop back to the dashboard (which re-fetches on resume) instead
    // of leaving the user on a now-stale profile screen for a
    // deleted child.
    navigator.popUntil((r) => r.isFirst);
  }

  // ── Presentational level layer over the child's real streak ───────
  // No new services: level, XP band and badge count are derived from
  // the streak this screen already has on widget.child.
  int get _streak => widget.child.streakCount;
  int get _level => (_streak ~/ 3) + 1;
  int get _xpBand => 300;
  int get _xpIntoLevel => (_streak % 3) * 100;
  int get _xpToNext => _xpBand - _xpIntoLevel;
  String get _levelTitle => _level >= 8
      ? 'Focus Master'
      : _level >= 5
      ? 'Focus Pro'
      : 'Focus Explorer';
  int get _badges =>
      const [3, 7, 14, 30, 60, 100].where((t) => _streak >= t).length;

  @override
  Widget build(BuildContext context) {
    final childName = widget.child.name;
    final accent = kidColors[_selectedColor];
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Me', style: AppText.screenTitle()),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: 12,
        ),
        children: [
          _buildHero(childName, accent),
          const SizedBox(height: AppSpacing.blockGap),
          _buildLevelCard(),
          const SizedBox(height: AppSpacing.blockGap),
          _buildStats(),
          const SizedBox(height: AppSpacing.blockGap),
          _buildMyApp(accent),
          const SizedBox(height: AppSpacing.blockGap),
          DfButton(
            'Save',
            icon: LucideIcons.check,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 24),
          // Parent-facing: remove this kid. Kept subtle so it doesn't
          // compete with the kid-facing content above.
          Center(
            child: TextButton.icon(
              onPressed: _deleteChild,
              style: TextButton.styleFrom(foregroundColor: AppColors.dangerFg),
              icon: const Icon(LucideIcons.trash2, size: 15),
              label: Text('Remove $childName'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Identity hero — avatar with a level badge, name, focus title.
  Widget _buildHero(String childName, Color accent) {
    return DfCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.avatarKid),
                ),
                alignment: Alignment.center,
                child: Text(
                  kidEmojis[_selectedEmoji],
                  style: const TextStyle(fontSize: 40),
                ),
              ),
              Positioned(
                bottom: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.card, width: 2),
                  ),
                  child: Text(
                    'Lv $_level',
                    style: AppText.caption(
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(childName, style: AppText.title(size: 22)),
          const SizedBox(height: 2),
          Text(
            _levelTitle,
            style: AppText.bodySecondary(color: AppColors.green),
          ),
        ],
      ),
    );
  }

  /// Level progress + a nudge on how to earn the next XP.
  Widget _buildLevelCard() {
    final frac = (_xpIntoLevel / _xpBand).clamp(0.0, 1.0);
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Level $_level', style: AppText.cardHeader()),
              Text(
                '$_xpToNext XP to Level ${_level + 1}',
                style: AppText.bodySecondary(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 10,
              backgroundColor: AppColors.border2,
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                LucideIcons.sparkles,
                size: 15,
                color: AppColors.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Finish today’s tasks to earn +30 XP',
                  style: AppText.body(size: 13.5, color: AppColors.ink70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Streak / level / badges stat row.
  Widget _buildStats() {
    return DfCard(
      child: Row(
        children: [
          Expanded(
            child: DfStatTile(
              '$_streak',
              'streak',
              valueColor: AppColors.amber,
              align: CrossAxisAlignment.center,
            ),
          ),
          _statDivider(),
          Expanded(
            child: DfStatTile(
              '$_level',
              'level',
              align: CrossAxisAlignment.center,
            ),
          ),
          _statDivider(),
          Expanded(
            child: DfStatTile(
              '$_badges',
              'badges',
              valueColor: AppColors.green,
              align: CrossAxisAlignment.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 34, color: AppColors.border2);

  /// "My app" — kid-safe toggles: Sounds + Avatar color (and emoji).
  Widget _buildMyApp(Color accent) {
    return DfCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DfSectionLabel('My app'),
          // Name (kept so _save's rename wiring stays reachable).
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(LucideIcons.user, size: 18),
              isDense: true,
            ),
          ),
          const SizedBox(height: 6),
          // Sounds — a kid-safe, presentation-only toggle.
          const _ToggleRow(icon: LucideIcons.volume2, label: 'Sounds'),
          const Divider(height: 24),
          Row(
            children: [
              const Icon(LucideIcons.palette, size: 18, color: AppColors.ink70),
              const SizedBox(width: 10),
              Text('Avatar color', style: AppText.listTitle()),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(
              kidColors.length,
              (i) => GestureDetector(
                onTap: () => setState(() => _selectedColor = i),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kidColors[i],
                    shape: BoxShape.circle,
                    border: _selectedColor == i
                        ? Border.all(color: AppColors.ink, width: 3)
                        : Border.all(color: AppColors.borderCol),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(LucideIcons.smile, size: 18, color: AppColors.ink70),
              const SizedBox(width: 10),
              Text('Avatar', style: AppText.listTitle()),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(
              kidEmojis.length,
              (i) => GestureDetector(
                onTap: () => setState(() => _selectedEmoji = i),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _selectedEmoji == i
                        ? accent.withValues(alpha: 0.15)
                        : AppColors.paper,
                    borderRadius: BorderRadius.circular(AppRadius.small),
                    border: Border.all(
                      color: _selectedEmoji == i ? accent : AppColors.borderCol,
                      width: _selectedEmoji == i ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    kidEmojis[i],
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A kid-safe toggle row with local (presentation-only) state.
class _ToggleRow extends StatefulWidget {
  final IconData icon;
  final String label;
  const _ToggleRow({required this.icon, required this.label});

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  bool _on = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: AppColors.ink70),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.label, style: AppText.listTitle())),
          Switch(
            value: _on,
            activeThumbColor: AppColors.green,
            onChanged: (v) => setState(() => _on = v),
          ),
        ],
      ),
    );
  }
}
