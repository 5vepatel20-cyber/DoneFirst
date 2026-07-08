import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/blocking_service.dart';
import '../services/lock_preset_service.dart';
import '../theme/app_theme.dart';
import '../models/app_pack.dart';
import 'lock_active_screen.dart';
import '../models/models.dart';

class LockConfigScreen extends StatefulWidget {
  final String childId;
  final String childName;
  const LockConfigScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<LockConfigScreen> createState() => _LockConfigScreenState();
}

class _LockConfigScreenState extends State<LockConfigScreen> {
  final _sessionService = SessionService();
  final _blockingService = BlockingService();
  final _presetService = LockPresetService();
  int _minLock = 60;
  int _maxLift = 120;
  String _approvalMode = 'balanced';
  final Set<String> _selectedPacks = {};
  List<LockPreset> _presets = [];
  bool _loadingPresets = false;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    setState(() => _loadingPresets = true);
    try {
      _presets = await _presetService.getPresets();
    } catch (_) {}
    if (mounted) setState(() => _loadingPresets = false);
  }

  Future<void> _savePreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Preset'),
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
      for (final p in preset.selectedPacks) {
        _selectedPacks.add(p);
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
      appBar: AppBar(title: Text('Lock — ${widget.childName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Duration'),
          const SizedBox(height: 8),
          Text(
            'Minimum lock time',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 30, label: Text('30m')),
              ButtonSegment(value: 45, label: Text('45m')),
              ButtonSegment(value: 60, label: Text('1h')),
              ButtonSegment(value: 90, label: Text('1.5h')),
              ButtonSegment(value: 120, label: Text('2h')),
            ],
            selected: {_minLock},
            onSelectionChanged: (v) => setState(() => _minLock = v.first),
          ),
          const SizedBox(height: 16),
          Text(
            'Auto-lift after (optional)',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Never')),
              ButtonSegment(value: 90, label: Text('90m')),
              ButtonSegment(value: 120, label: Text('2h')),
              ButtonSegment(value: 180, label: Text('3h')),
            ],
            selected: {_maxLift},
            onSelectionChanged: (v) =>
                setState(() => _maxLift = v.first == 0 ? 0 : v.first),
          ),
          const SizedBox(height: 24),
          _section('Approval Mode'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'strict', label: Text('Strict')),
              ButtonSegment(value: 'balanced', label: Text('Balanced')),
              ButtonSegment(value: 'parent_only', label: Text('Parent Only')),
            ],
            selected: {_approvalMode},
            onSelectionChanged: (v) => setState(() => _approvalMode = v.first),
          ),
          const SizedBox(height: 4),
          Text(
            _approvalMode == 'strict'
                ? 'Apps locked for full min duration even if homework done early.'
                : _approvalMode == 'balanced'
                ? 'Apps unlock early if proof approved and minimum time passed.'
                : 'Apps unlock only after parent approves each proof.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _section('Presets'),
          const SizedBox(height: 8),
          if (_loadingPresets)
            const Center(child: CircularProgressIndicator())
          else if (_presets.isNotEmpty) ...[
            SizedBox(
              height: 60,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _presets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final p = _presets[i];
                  return InputChip(
                    label: Text(p.name),
                    onPressed: () => _loadPreset(p),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => _deletePreset(p.id),
                  );
                },
              ),
            ),
          ] else
            const Text(
              'Save your current settings as a preset for quick reuse',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _savePreset,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save Current as Preset'),
          ),
          const SizedBox(height: 24),
          _section('Apps to Block'),
          const SizedBox(height: 8),
          Text(
            'Select distraction packs',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ...AppPack.defaults.map(
            (pack) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: CheckboxListTile(
                title: Text(
                  pack.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  pack.description,
                  style: const TextStyle(fontSize: 12),
                ),
                secondary: Icon(
                  pack.icon,
                  color: AppColors.primary.withOpacity(0.7),
                ),
                value: _selectedPacks.contains(pack.name),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedPacks.add(pack.name);
                    } else {
                      _selectedPacks.remove(pack.name);
                    }
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _startLock,
            icon: const Icon(Icons.lock),
            label: Text(
              _selectedPacks.isEmpty
                  ? 'Start Homework Lock'
                  : 'Lock ${_selectedPacks.length} pack(s)',
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Future<void> _startLock() async {
    final session = await _sessionService.startSession(
      childId: widget.childId,
      minLockMinutes: _minLock,
      maxLiftMinutes: _maxLift,
      approvalMode: _approvalMode,
    );
    // Try to start blocking on this device. If it fails (permission
    // denied or plugin error), warn the parent but still proceed —
    // blocking happens on the kid's device when they open the app.
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
