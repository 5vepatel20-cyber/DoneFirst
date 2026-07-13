import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app_globals.dart' as app;
import '../screens/kid_device_pairing_screen.dart';
import '../services/kid_device_service.dart';
import '../theme/app_theme.dart';

/// Compact "Recent activity" card surfaced on the parent dashboard
/// when there are kid-device events to show. Shows the most recent
/// 3 events with the same icon/colour mapping the pairing screen's
/// full activity feed uses, plus a "View all" tap target that
/// pushes the pairing screen.
///
/// Hidden when there are no events (so a freshly-paired family
/// doesn't see an empty card on day one). Auto-refreshes every
/// 30s while mounted so the timestamps stay accurate.
class RecentKidDeviceActivityCard extends StatefulWidget {
  /// Number of events to fetch + display. Capped at 5 to keep the
  /// card from outgrowing the schedule hero above it.
  final int limit;

  const RecentKidDeviceActivityCard({super.key, this.limit = 3});

  @override
  State<RecentKidDeviceActivityCard> createState() =>
      _RecentKidDeviceActivityCardState();
}

class _RecentKidDeviceActivityCardState
    extends State<RecentKidDeviceActivityCard> {
  final _eventService = KidDeviceEventService();
  List<KidDeviceEvent> _events = const [];
  bool _loading = true;
  bool _error = false;
  void Function(Map<String, dynamic>)? _previousOnNewEvent;

  @override
  void initState() {
    super.initState();
    _load();
    // Chain into the realtime callback slot so the card refreshes
    // whenever a new event lands. The toast listener higher in the
    // tree also subscribes; the save-previous / restore-on-dispose
    // pattern keeps both wired without one starving the other.
    _previousOnNewEvent = app.realtimeService.onNewKidDeviceEvent;
    app.realtimeService.onNewKidDeviceEvent = _onRealtimeEvent;
  }

  @override
  void dispose() {
    app.realtimeService.onNewKidDeviceEvent = _previousOnNewEvent;
    super.dispose();
  }

  void _onRealtimeEvent(Map<String, dynamic> newRow) {
    // Chain first so other subscribers (toast listener, activity
    // feed) don't get starved.
    _previousOnNewEvent?.call(newRow);
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _eventService.listFamilyEvents(limit: widget.limit);
      if (!mounted) return;
      setState(() {
        _events = list;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading and error both collapse to a thin placeholder so the
    // dashboard doesn't reflow when the fetch fails or is mid-flight.
    if (_loading) {
      return const SizedBox.shrink();
    }
    if (_error || _events.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  LucideIcons.activity,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 6),
                Text(
                  'RECENT ACTIVITY',
                  style: AppText.eyebrow(),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'View all',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._events.map((e) => _ActivityRow(event: e)),
          ],
        ),
      ),
    );
  }

  void _openAll() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const KidDevicePairingScreen()),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final KidDeviceEvent event;
  const _ActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _iconFor(event.eventType);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: Icon(icon, size: 12, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              event.label(),
              style: AppText.body(size: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.ageLabel(DateTime.now()),
            style: AppText.bodySecondary(size: 11),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _iconFor(String type) {
    switch (type) {
      case KidDeviceEvent.typeDeviceRevoked:
        return (LucideIcons.shieldOff, AppColors.danger);
      case KidDeviceEvent.typeCodeClaimed:
        return (LucideIcons.link, AppColors.ok);
      case KidDeviceEvent.typeCodeGenerated:
        return (LucideIcons.plusCircle, AppColors.warn);
      case KidDeviceEvent.typeCodeCancelled:
        return (LucideIcons.xCircle, AppColors.muted);
      default:
        return (LucideIcons.circle, AppColors.faint);
    }
  }
}