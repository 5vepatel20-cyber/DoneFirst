import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/blocking_service.dart';
import '../theme/app_theme.dart';
import '../models/app_pack.dart';
import 'lock_active_screen.dart';

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
  int _minLock = 60;
  int _maxLift = 120;
  String _approvalMode = 'balanced';
  final Set<String> _selectedPacks = {};

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
    await _blockingService.startBlocking();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LockActiveScreen(
            sessionId: session['id'],
            childName: widget.childName,
          ),
        ),
      );
    }
  }
}
