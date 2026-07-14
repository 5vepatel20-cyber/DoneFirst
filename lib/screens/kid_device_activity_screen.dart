import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../app_globals.dart' as app;
import '../services/kid_device_service.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

/// Full-screen activity log for kid-device events: pairings,
/// claims, cancellations, revokes. Reachable from the dashboard's
/// "View all" link in the recent activity card. The pairing
/// screen also renders an 8-row activity section, but pairing is
/// about managing devices — for the *history* view, this screen
/// is the right surface (more events, no pairing chrome).
///
/// Live-updates via the same RealtimeService callback-chain
/// pattern used by the recent-activity card: we save the prior
/// handler on mount, install our own, and restore on dispose.
/// New events trigger a refetch (rather than incremental
/// prepend), which is cheap — the table is bounded to 25 events
/// in the view and the parent is unlikely to be tailing it.
class KidDeviceActivityScreen extends StatefulWidget {
  const KidDeviceActivityScreen({super.key});

  @override
  State<KidDeviceActivityScreen> createState() =>
      _KidDeviceActivityScreenState();
}

class _KidDeviceActivityScreenState extends State<KidDeviceActivityScreen> {
  final _eventService = KidDeviceEventService();
  List<KidDeviceEvent> _events = const [];
  bool _loading = true;
  // True only after a load attempt has failed. Distinct from
  // _loading (the initial in-flight state) so the empty-state
  // copy can differ between "haven't loaded yet" (show spinner)
  // and "tried to load and got an error" (show retry).
  bool _error = false;
  void Function(Map<String, dynamic>)? _previousOnNewEvent;

  @override
  void initState() {
    super.initState();
    _load();
    _previousOnNewEvent = app.realtimeService.onNewKidDeviceEvent;
    app.realtimeService.onNewKidDeviceEvent = _onRealtimeEvent;
  }

  @override
  void dispose() {
    app.realtimeService.onNewKidDeviceEvent = _previousOnNewEvent;
    super.dispose();
  }

  void _onRealtimeEvent(Map<String, dynamic> newRow) {
    // Chain first so the toast listener higher in the tree and
    // any other subscribers still see the event.
    _previousOnNewEvent?.call(newRow);
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _eventService.listFamilyEvents(limit: 50);
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: LucideIcons.alertCircle,
                        title: 'Could not load activity',
                        subtitle: 'Pull down to try again',
                      ),
                    ],
                  )
                : _events.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          EmptyState(
                            icon: LucideIcons.history,
                            title: 'No activity yet',
                            subtitle:
                                'Pairings, claims, and revokes show up '
                                'here once you start using kid devices.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: _events.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          return _ActivityRow(event: _events[i]);
                        },
                      ),
      ),
    );
  }
}

/// One row in the activity log. Mirrors the styling used by the
/// pairing screen's recent-activity section so the two surfaces
/// read as the same family of UI. Kept private to this screen —
/// if a future caller needs the same row shape, lift it into
/// widgets/ then.
class _ActivityRow extends StatelessWidget {
  final KidDeviceEvent event;
  const _ActivityRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (event.eventType) {
      KidDeviceEvent.typeCodeGenerated => (
          LucideIcons.plusCircle,
          AppColors.warn
        ),
      KidDeviceEvent.typeCodeClaimed => (LucideIcons.link, AppColors.ok),
      KidDeviceEvent.typeCodeCancelled => (
          LucideIcons.xCircle,
          AppColors.muted
        ),
      KidDeviceEvent.typeDeviceRevoked => (
          LucideIcons.shieldOff,
          AppColors.danger
        ),
      _ => (LucideIcons.circle, AppColors.faint),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.hair2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              event.label(),
              style: AppText.body(size: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            event.ageLabel(DateTime.now()),
            style: AppText.bodySecondary(size: 12),
          ),
        ],
      ),
    );
  }
}
