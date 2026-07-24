import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../services/session_service.dart';
import '../services/blocking_service.dart';
import '../services/lock_preset_service.dart';
import '../services/kid_device_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';
import '../widgets/pin_guard.dart';
import '../widgets/kid_device_lock_config_banner.dart';
import '../widgets/destructive_confirm_dialog.dart';
import 'kid_device_pairing_screen.dart';
import 'lock_active_screen.dart';
import 'device_permissions_screen.dart';
import '../models/models.dart';

class LockConfigScreen extends StatefulWidget {
  final String childId;
  final String childName;
  // Optional pre-fill values. When supplied (e.g. from
  // SchedulesScreen "Start Now" tapping today's schedule), the
  // form opens with these defaults selected so the parent doesn't
  // re-pick values the schedule already specified. Falls back to
  // balanced/60/120 when not provided — same as the original
  // hard-coded defaults.
  final int? initialMinLock;
  final int? initialMaxLift;
  final String? initialApprovalMode;

  const LockConfigScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.initialMinLock,
    this.initialMaxLift,
    this.initialApprovalMode,
  });

  @override
  State<LockConfigScreen> createState() => _LockConfigScreenState();
}

class _LockConfigScreenState extends State<LockConfigScreen> {
  final _sessionService = SessionService();
  final _blockingService = BlockingService();
  final _presetService = LockPresetService();
  final _kidDeviceService = KidDeviceService();
  late int _minLock;
  late int _maxLift;
  late String _approvalMode;
  final Set<String> _selectedPacks = {};
  List<LockPreset> _presets = [];
  bool _loadingPresets = false;
  bool _kidDeviceChecked = false;
  // Resolved to a non-revoked device for this child when one is
  // paired. Null means either no device is paired or the only one
  // was revoked — both states trigger the warning banner above the
  // Start button. Loaded async so it doesn't block the form.
  KidDevice? _kidDevice;

  @override
  void initState() {
    super.initState();
    _minLock = widget.initialMinLock ?? 60;
    _maxLift = widget.initialMaxLift ?? 120;
    _approvalMode = widget.initialApprovalMode ?? 'balanced';
    _loadPresets();
    _loadKidDevice();
  }

  Future<void> _loadPresets() async {
    setState(() => _loadingPresets = true);
    try {
      _presets = await _presetService.getPresets();
    } catch (_) {}
    if (mounted) setState(() => _loadingPresets = false);
  }

  /// Resolves whether this child has a paired, non-revoked kid
  /// device. Used to decide whether the warning banner above the
  /// Start button needs to fire. Fail-soft: any RLS hiccup or
  /// network blip leaves `_kidDevice` as null (which *does* show
  /// the banner) — a false positive is safer than a false negative
  /// here, since the cost of an unpaired kid device is a lock that
  /// only takes effect on the parent's phone.
  Future<void> _loadKidDevice() async {
    try {
      final devices = await _kidDeviceService.listDevicesForChild(
        widget.childId,
      );
      final active = devices.where((d) => !d.isRevoked).firstOrNull;
      if (mounted) {
        setState(() {
          _kidDevice = active;
          // Marked on every attempt (success or empty) so the
          // Start Lock button only enables once we know whether a
          // kid device exists. Without this the parent could tap
          // Start in the race window before the device list
          // returned, leading to a flash of local flutter_screentime
          // even when a kid device was actually paired.
          _kidDeviceChecked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _kidDeviceChecked = true);
    }
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save preset'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              hintText: 'e.g. Weekday Homework',
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
      if (name != null && name.isNotEmpty) {
        // createPreset + _loadPresets can throw on a network blip
        // or RLS hiccup. The finally block disposes the controller
        // on every exit path; the catch surfaces a snackbar so the
        // parent knows the save failed instead of staring at a
        // silent spinner. (Bug audit 2026-07 pattern #1.)
        try {
          await _presetService.createPreset(
            name: name,
            minLockMinutes: _minLock,
            maxLiftMinutes: _maxLift,
            approvalMode: _approvalMode,
            selectedPacks: _selectedPacks.toList(),
          );
          await _loadPresets();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Preset saved!')));
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Couldn’t save preset: $e')));
        }
      }
    } finally {
      // Dialog controller is local-scope; dispose on every exit
      // path (save, cancel, throw). Avoids leaking one controller
      // per saved preset across a long session.
      controller.dispose();
    }
  }

  Future<void> _loadPreset(LockPreset preset) async {
    setState(() {
      _minLock = preset.minLockMinutes;
      _maxLift = preset.maxLiftMinutes;
      _approvalMode = preset.approvalMode;
      _selectedPacks.clear();
      // selectedPacks is List<String> (pack names), not
      // List<AppPack>, so copy directly.
      for (final name in preset.selectedPacks) {
        _selectedPacks.add(name);
      }
    });
  }

  Future<void> _deletePreset(LockPreset preset) async {
    final confirmed = await DestructiveConfirmDialog.show(
      context,
      title: 'Delete preset “${preset.name}”?',
      description:
          'This preset stores your saved duration, lift window, '
          'approval mode, and blocked-app packs. You can re-create '
          'it later, but any customizations (like “Math + Reading '
          'only”) will be lost.',
      confirmPhrase: preset.name,
      confirmButtonLabel: 'Delete preset',
    );
    if (!confirmed) return;
    try {
      await _presetService.deletePreset(preset.id);
      await _loadPresets();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Couldn’t delete preset: $e')));
    }
  }

  // ── Preset-card helpers ─────────────────────────────────────────────
  // The three mock preset cards ("After school", "Quick", "Custom") are
  // pure quick-setters over the existing _minLock / _selectedPacks state
  // so no new state field is introduced. Active choice is derived from
  // _minLock: 45 → after school, 25 → quick, anything else → custom.
  String get _activePreset {
    if (_minLock == 45) return 'after_school';
    if (_minLock == 25) return 'quick';
    return 'custom';
  }

  static const _afterSchoolPacks = {'Social Media', 'Games', 'Entertainment'};

  void _chooseAfterSchool() {
    setState(() {
      _minLock = 45;
      _selectedPacks
        ..clear()
        ..addAll(_afterSchoolPacks);
    });
  }

  void _chooseQuick() => setState(() => _minLock = 25);

  void _chooseCustom() {
    // Only nudge off a preset value; if the parent is already on a
    // custom duration, leave it untouched.
    if (_minLock == 45 || _minLock == 25) {
      setState(() => _minLock = 60);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCustom = _activePreset == 'custom';
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Close',
        ),
        title: Text('Start focus', style: AppText.screenTitle(size: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          4,
          AppSpacing.screenPadding,
          28,
        ),
        children: [
          Text('One preset, one tap. No forms.', style: AppText.body(size: 15)),
          const SizedBox(height: 20),
          _buildForKid(),
          const SizedBox(height: 22),
          _buildPresetSection(),
          if (isCustom) ...[const SizedBox(height: 20), _buildFineTune()],
          const SizedBox(height: 22),
          _buildWhoApproves(),
          const SizedBox(height: 24),
          if (_kidDevice == null) ...[
            _buildNoKidDeviceBanner(),
            const SizedBox(height: 12),
          ],
          _buildStartButton(),
        ],
      ),
    );
  }

  // ── For <kid> ───────────────────────────────────────────────────────
  Widget _buildForKid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DfSectionLabel('For'),
        DfCard(
          padding: const EdgeInsets.all(12),
          borderColor: AppColors.green,
          child: Row(
            children: [
              DfAvatar(widget.childName, size: 42, circle: true),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.childName, style: AppText.cardHeader()),
              ),
              const Icon(LucideIcons.check, size: 18, color: AppColors.green),
            ],
          ),
        ),
      ],
    );
  }

  // ── Preset ──────────────────────────────────────────────────────────
  Widget _buildPresetSection() {
    final active = _activePreset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DfSectionLabel('Preset'),
        _PresetCard(
          selected: active == 'after_school',
          onTap: _chooseAfterSchool,
          title: 'After school',
          trailing: '45 min',
          subtitle: 'Blocks social, games & video until work’s approved',
          chips: const ['Social', 'Games', 'Video'],
        ),
        const SizedBox(height: 10),
        _PresetCard(
          selected: active == 'quick',
          onTap: _chooseQuick,
          title: 'Quick',
          trailing: '25m',
        ),
        const SizedBox(height: 10),
        _PresetCard(
          selected: active == 'custom',
          onTap: _chooseCustom,
          title: 'Custom',
          trailing: null,
        ),
      ],
    );
  }

  // ── Custom fine-tune (min lock · auto lift · apps · presets) ─────────
  Widget _buildFineTune() {
    return DfCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MINIMUM LOCK', style: AppText.eyebrow()),
          const SizedBox(height: 8),
          DfSegmented<int>(
            options: const [
              (value: 30, label: '30m'),
              (value: 45, label: '45m'),
              (value: 60, label: '1h'),
              (value: 90, label: '1.5h'),
              (value: 120, label: '2h'),
            ],
            selected: _minLock,
            onChanged: (v) => setState(() => _minLock = v),
          ),
          const SizedBox(height: 18),
          Text('AUTO LIFT AFTER (OPTIONAL)', style: AppText.eyebrow()),
          const SizedBox(height: 8),
          DfSegmented<int>(
            options: const [
              (value: 0, label: 'Never'),
              (value: 90, label: '90m'),
              (value: 120, label: '2h'),
              (value: 180, label: '3h'),
            ],
            selected: _maxLift,
            onChanged: (v) => setState(() => _maxLift = v),
          ),
          const SizedBox(height: 18),
          Text('APPS TO BLOCK', style: AppText.eyebrow()),
          const SizedBox(height: 4),
          Text(
            'Pick the distraction categories to pause during this session.',
            style: AppText.bodySecondary(size: 12.5),
          ),
          const SizedBox(height: 12),
          ...AppPack.defaults.map((pack) {
            final selected = _selectedPacks.contains(pack.name);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PackRow(
                pack: pack,
                selected: selected,
                onTap: () => setState(() {
                  if (selected) {
                    _selectedPacks.remove(pack.name);
                  } else {
                    _selectedPacks.add(pack.name);
                  }
                }),
              ),
            );
          }),
          const SizedBox(height: 8),
          _buildPresets(),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRESETS', style: AppText.eyebrow()),
        const SizedBox(height: 10),
        if (_loadingPresets)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (_presets.isEmpty)
          Text(
            'Save your current settings as a preset for quick reuse.',
            style: AppText.bodySecondary(size: 12.5),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets
                .map(
                  (p) => _PresetChip(
                    label: p.name,
                    onTap: () => _loadPreset(p),
                    onDelete: () => _deletePreset(p),
                  ),
                )
                .toList(),
          ),
        const SizedBox(height: 12),
        DfButton.outline(
          'Save current as preset',
          icon: LucideIcons.bookmark,
          expand: false,
          onPressed: _savePreset,
        ),
      ],
    );
  }

  // ── Who approves ────────────────────────────────────────────────────
  Widget _buildWhoApproves() {
    // Maps the mock's three labels onto the existing approvalMode
    // string values so startSession keeps receiving the same values:
    //   balanced    → "AI + you"  (proof approved + minimum time)
    //   parent_only → "You"       (parent approves each proof)
    //   strict      → "Auto"      (auto-unlocks after the full duration)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DfSectionLabel('Who approves'),
        DfSegmented<String>(
          options: const [
            (value: 'balanced', label: 'AI + you'),
            (value: 'parent_only', label: 'You'),
            (value: 'strict', label: 'Auto'),
          ],
          selected: _approvalMode,
          onChanged: (v) => setState(() => _approvalMode = v),
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return DfButton(
      'Start · lock ${widget.childName}’s apps',
      icon: LucideIcons.lock,
      // Disabled until the kid-device lookup finishes, so the
      // gate inside _startLock can trust _kidDevice (otherwise
      // we'd race a flash of local flutter_screentime on every
      // Lock tap while the device list is still in flight).
      onPressed: _kidDeviceChecked ? _startLock : null,
    );
  }

  /// Last-second heads-up before the parent commits to starting a
  /// lock. Rendered just above the Start button so the warning is
  /// the last thing the parent sees before tapping, mirroring the
  /// same pattern as `lock_active_screen.dart`'s no-device banner.
  /// Different copy: there we say "won't be enforced on the kid's
  /// phone" because the lock is already running; here it's
  /// pre-flight so we tell the parent they can fix it now and skip
  /// the surprise.
  Widget _buildNoKidDeviceBanner() {
    return KidDeviceLockConfigBanner(
      childName: widget.childName,
      onPair: _openPairing,
    );
  }

  /// PIN-gated push to the pairing screen, preselecting this
  /// child so the parent doesn't have to re-pick. Mirrors the
  /// pattern used by `kid_device_setup_hint_card.dart` →
  /// `_openPairing`.
  void _openPairing() {
    PinGuard.push(
      context,
      destination: KidDevicePairingScreen(preselectChildId: widget.childId),
      title: 'Confirm to pair a kid device',
    );
  }

  Future<void> _startLock() async {
    // Two paths converge here:
    //
    //   1. **Kid device paired** — skip the permission gate entirely.
    //      Enforcement rides on Supabase realtime to the kid app's own
    //      flutter_screentime + kiosk lock-task, so the parent device's
    //      own usage-stats / overlay grants don't matter.
    //
    //   2. **Single-device mode** (no kid device) — we have to block
    //      apps on the parent's phone, which needs the OS grants. If
    //      they aren't there, route through DevicePermissionsScreen
    //      and only proceed once the parent has flipped both toggles.
    //
    // The previous version created the homework_sessions row BEFORE
    // the permission check, which leaked an `active` row into the DB
    // every time a parent hit "back" out of the permissions screen.
    // The kid device's realtime subscription also saw that phantom
    // session, briefly flashing the lock UI on the kid phone. Fix is
    // to defer the insert until the gates have actually passed.
    if (!shouldSkipLocalBlockingOnKidDevice(_kidDevice)) {
      final granted = await _blockingService.currentPermissions();
      final allGranted =
          granted.values.isNotEmpty && granted.values.every((g) => g);
      if (!allGranted) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DevicePermissionsScreen(
              // Continue → run the rest of the lock start (startBlocking
              // + session insert + navigate). If the parent backs out of
              // the permissions screen instead of granting, no session
              // row is ever created — the gate is the gate.
              onContinue: () => _actuallyStartLock(),
            ),
          ),
        );
        return;
      }
      final blocked = await _blockingService.startBlocking();
      if (!blocked && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _blockingService.lastError ??
                  'App blocking could not start on this device. The kid\'s '
                      'device needs the permission granted separately.',
            ),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
    await _actuallyStartLock();
  }

  /// Create the homework_sessions row and navigate to the live lock
  /// screen. Split out of [_startLock] so the permission-gate path
  /// can call it from inside DevicePermissionsScreen.onContinue
  /// without re-running the gate — that would re-open the
  /// permissions screen recursively if the user took a moment.
  Future<void> _actuallyStartLock() async {
    final session = await _sessionService.startSession(
      childId: widget.childId,
      minLockMinutes: _minLock,
      maxLiftMinutes: _maxLift,
      approvalMode: _approvalMode,
    );
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LockActiveScreen(
          sessionId: session.id,
          childName: widget.childName,
        ),
      ),
    );
  }
}

/// One preset choice — "After school", "Quick", "Custom". A warm card
/// that tints emerald + shows a check when it's the active choice.
class _PresetCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? trailing;
  final String? subtitle;
  final List<String> chips;

  const _PresetCard({
    required this.selected,
    required this.onTap,
    required this.title,
    this.trailing,
    this.subtitle,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    return DfCard(
      onTap: onTap,
      color: selected ? AppColors.greenTint : AppColors.card,
      borderColor: selected ? AppColors.green : AppColors.borderCol,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RadioDot(selected: selected),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: AppText.cardHeader())),
              if (trailing != null)
                Text(
                  trailing!,
                  style: AppText.listTitle(color: AppColors.green),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const Padding(
              padding: EdgeInsets.only(left: 32),
              child: SizedBox(height: 6),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Text(subtitle!, style: AppText.bodySecondary(size: 12.5)),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips
                    .map((c) => DfStatusPill(c, tone: DfPillTone.neutral))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.green : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.green : AppColors.inkFaint,
          width: 1.6,
        ),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
          : null,
    );
  }
}

/// Saved-preset pill — tap the body to load, the X to delete.
class _PresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _PresetChip({
    required this.label,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(color: AppColors.borderCol, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.listTitle(size: 14)),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: const Icon(
                LucideIcons.x,
                size: 13,
                color: AppColors.ink45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One "Apps to block" category row inside the custom fine-tune card.
class _PackRow extends StatelessWidget {
  final AppPack pack;
  final bool selected;
  final VoidCallback onTap;

  const _PackRow({
    required this.pack,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.greenTint : AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(
            color: selected ? AppColors.green : AppColors.borderCol,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.greenTint,
                borderRadius: BorderRadius.circular(AppRadius.iconTile),
              ),
              alignment: Alignment.center,
              child: Icon(pack.icon, size: 20, color: AppColors.green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pack.name, style: AppText.listTitle(size: 14)),
                  const SizedBox(height: 2),
                  Text(
                    pack.description,
                    style: AppText.bodySecondary(size: 11.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _RadioDot(selected: selected),
          ],
        ),
      ),
    );
  }
}
