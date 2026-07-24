import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_globals.dart' as app;
import '../services/kid_device_service.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

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
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const _LoadingList()
            : _error
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 80),
                  DfEmptyState(
                    icon: LucideIcons.alertCircle,
                    title: 'Couldn’t load activity',
                    hint:
                        'Something went wrong. Pull down or tap '
                        'to try again.',
                    ctaLabel: 'Try again',
                    onCta: _load,
                  ),
                ],
              )
            : _events.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 80),
                  DfEmptyState(
                    icon: LucideIcons.history,
                    title: 'No activity yet',
                    hint:
                        'Pairings, claims, and revokes show up '
                        'here once you start using kid devices.',
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  14,
                  AppSpacing.screenPadding,
                  32,
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
        LucideIcons.keyRound,
        AppColors.green,
      ),
      KidDeviceEvent.typeCodeClaimed => (LucideIcons.link, AppColors.green),
      KidDeviceEvent.typeCodeCancelled => (LucideIcons.x, AppColors.ink45),
      KidDeviceEvent.typeDeviceRevoked => (
        LucideIcons.shieldOff,
        AppColors.dangerFg,
      ),
      _ => (LucideIcons.circle, AppColors.ink45),
    };
    return DfCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.small),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              event.label(),
              style: AppText.body(size: 14, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 10),
          Text(event.ageLabel(DateTime.now()), style: AppText.label(size: 11)),
        ],
      ),
    );
  }
}

/// Skeleton placeholder rows shown during the first load.
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        14,
        AppSpacing.screenPadding,
        32,
      ),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => Container(
        height: 58,
        decoration: BoxDecoration(
          color: AppColors.border2,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
    );
  }
}
