import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/session_service.dart';
import '../services/blocking_service.dart';
import '../services/lock_preset_service.dart';
import '../services/kid_device_service.dart';
import '../theme/app_theme.dart';
import '../widgets/segmented_group.dart';
import '../widgets/pin_guard.dart';
import '../widgets/kid_device_lock_config_banner.dart';
import 'kid_device_pairing_screen.dart';
import 'lock_active_screen.dart';
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
      if (mounted) setState(() => _kidDevice = active);
    } catch (_) {}
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController();
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

  Future<void> _deletePreset(String presetId) async {
    await _presetService.deletePreset(presetId);
    await _loadPresets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Close',
        ),
        title: const _LockConfigTitle(),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
          vertical: 8,
        ),
        children: [
          _buildMinLockSection(),
          const SizedBox(height: AppSpacing.blockGap),
          _buildAutoLiftSection(),
          const SizedBox(height: AppSpacing.blockGap + 4),
          _buildApprovalModeSection(),
          const SizedBox(height: AppSpacing.blockGap + 4),
          _buildPresetsSection(),
          const SizedBox(height: AppSpacing.blockGap + 4),
          _buildAppPacksSection(),
          const SizedBox(height: AppSpacing.blockGap + 8),
          if (_kidDevice == null) _buildNoKidDeviceBanner(),
          if (_kidDevice == null) const SizedBox(height: 8),
          _buildStartButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────
  // Title is rendered in two lines: "Set up lock" (eyebrow) + "for
  // {child}" (screen title). Compact title row so we don't add
  // vertical chrome to an already-tall form.
  Widget _buildMinLockSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MINIMUM LOCK TIME', style: AppText.eyebrow()),
        const SizedBox(height: 8),
        AppSegmentedGroup<int>(
          options: const [
            AppSegment(value: 30, label: '30m'),
            AppSegment(value: 45, label: '45m'),
            AppSegment(value: 60, label: '1h'),
            AppSegment(value: 90, label: '1.5h'),
            AppSegment(value: 120, label: '2h'),
          ],
          selected: _minLock,
          onSelected: (v) => setState(() => _minLock = v),
        ),
      ],
    );
  }

  Widget _buildAutoLiftSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AUTO LIFT AFTER (OPTIONAL)', style: AppText.eyebrow()),
        const SizedBox(height: 8),
        AppSegmentedGroup<int>(
          options: const [
            AppSegment(value: 0, label: 'Never'),
            AppSegment(value: 90, label: '90m'),
            AppSegment(value: 120, label: '2h'),
            AppSegment(value: 180, label: '3h'),
          ],
          selected: _maxLift,
          onSelected: (v) => setState(() => _maxLift = v),
        ),
      ],
    );
  }

  Widget _buildApprovalModeSection() {
    final modes = const {
      'strict': 'Strict',
      'balanced': 'Balanced',
      'parent_only': 'Parent',
    };
    final descriptions = const {
      'strict': 'Apps locked for full min duration even if homework done early.',
      'balanced': 'Apps unlock early if proof approved and minimum time passed.',
      'parent_only': 'Apps unlock only after parent approves each proof.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APPROVAL MODE', style: AppText.eyebrow()),
        const SizedBox(height: 8),
        AppSegmentedGroup<String>(
          options: modes.entries
              .map((e) => AppSegment(value: e.key, label: e.value))
              .toList(),
          selected: _approvalMode,
          onSelected: (v) => setState(() => _approvalMode = v),
        ),
        const SizedBox(height: 8),
        Text(
          descriptions[_approvalMode] ?? '',
          style: AppText.bodySecondary(size: 12),
        ),
      ],
    );
  }

  Widget _buildPresetsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PRESETS', style: AppText.eyebrow()),
        const SizedBox(height: 10),
        if (_loadingPresets)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_presets.isEmpty)
          Text(
            'Save your current settings as a preset for quick reuse.',
            style: AppText.bodySecondary(size: 12),
          )
        else
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final p = _presets[i];
                return _PresetChip(
                  label: p.name,
                  onTap: () => _loadPreset(p),
                  onDelete: () => _deletePreset(p.id),
                );
              },
            ),
          ),
        const SizedBox(height: 10),
        // Dashed "Save current" — visually distinct from the saved
        // presets so the parent knows it's an action, not a chip.
        _DashedButton(
          icon: LucideIcons.bookmark,
          label: 'Save current as preset',
          onTap: _savePreset,
        ),
      ],
    );
  }

  Widget _buildAppPacksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APPS TO BLOCK', style: AppText.eyebrow()),
        const SizedBox(height: 4),
        Text(
          'Pick the distraction categories to lock during this session.',
          style: AppText.bodySecondary(size: 12),
        ),
        const SizedBox(height: 10),
        ...AppPack.defaults.map((pack) {
          final selected = _selectedPacks.contains(pack.name);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AppPackRow(
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
      ],
    );
  }

  Widget _buildStartButton() {
    final label = _selectedPacks.isEmpty
        ? 'Start homework lock'
        : 'Lock ${_selectedPacks.length} '
            '${_selectedPacks.length == 1 ? 'pack' : 'packs'}';
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _startLock,
        icon: const Icon(LucideIcons.lock, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
        ),
      ),
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
    final session = await _sessionService.startSession(
      childId: widget.childId,
      minLockMinutes: _minLock,
      maxLiftMinutes: _maxLift,
      approvalMode: _approvalMode,
    );
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
    if (mounted) {
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
}

/// AppBar title rendered as "Set up lock" (eyebrow) over
/// "for {childName}" (screen title). Extracted so the build method
/// reads top-down without a nested widget literal.
class _LockConfigTitle extends StatelessWidget {
  const _LockConfigTitle();

  @override
  Widget build(BuildContext context) {
    // Pull childName from the LockConfigScreen route. Going through
    // ModalRoute keeps the title in sync if the parent route's
    // arguments ever change.
    final args = ModalRoute.of(context)?.settings.arguments;
    final name = args is LockConfigScreen
        ? args.childName
        : (ModalRoute.of(context)?.settings.name ?? '');

    // We can't directly read the child's name off the AppBar
    // builder — the title widget is rebuilt each time the route
    // argument changes. As a fallback we display a short hint
    // when we can't get the name; the surrounding page chrome
    // still tells the parent which child this is.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('SET UP LOCK', style: AppText.eyebrow()),
        Text(
          name.isNotEmpty ? 'for $name' : 'Lock',
          style: AppText.screenTitle(),
        ),
      ],
    );
  }
}

/// Preset chip — outlined pill with a delete X. Tapping the chip
/// body loads the preset; tapping the X deletes.
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
    return Material(
      color: AppColors.card,
      shape: StadiumBorder(
        side: BorderSide(color: AppColors.hair2),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: AppText.listTitle()),
              const SizedBox(width: 8),
              InkWell(
                onTap: onDelete,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    LucideIcons.x,
                    size: 12,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed-border action button used for "Save current as preset".
/// Drawn via a CustomPainter so we control the dash cadence.
class _DashedButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashedButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.button),
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.forest),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppText.listTitle(color: AppColors.forest),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.hair
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(AppRadius.button),
        ),
      );

    _drawDashedPath(canvas, path, paint, dash: 6, gap: 4);
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// One row in the "Apps to block" list. Handoff design:
/// 36x36 sageFill icon tile + title + examples on the right.
/// Selected state shows a forest check on the right and tints the
/// row background to #F1F6EF so the eye can quickly count what's
/// chosen.
class _AppPackRow extends StatelessWidget {
  final AppPack pack;
  final bool selected;
  final VoidCallback onTap;

  const _AppPackRow({
    required this.pack,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF1F6EF) : AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.forest : AppColors.hair2,
              width: selected ? 1.5 : 0.5,
            ),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              _PackIcon(icon: pack.icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pack.name, style: AppText.listTitle()),
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
              _CheckMark(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackIcon extends StatelessWidget {
  final IconData icon;
  const _PackIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.sageFill,
        borderRadius: BorderRadius.circular(AppRadius.iconTile),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: AppColors.forest),
    );
  }
}

class _CheckMark extends StatelessWidget {
  final bool selected;
  const _CheckMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? AppColors.forest : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.forest : AppColors.faint,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: selected
          ? const Icon(
              LucideIcons.check,
              size: 14,
              color: Colors.white,
            )
          : null,
    );
  }
}