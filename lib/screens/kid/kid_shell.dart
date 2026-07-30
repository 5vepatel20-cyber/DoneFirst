import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_theme.dart';
import '../kid_history_screen.dart';
import 'kid_me_screen.dart';
import 'kid_settings_button.dart';
import 'kid_tasks_screen.dart';
import 'today_screen.dart';

/// The kid's free-time home, with the four-tab bar from the redesign:
/// Today · Tasks · Progress · Me.
///
/// WHY THIS EXISTS
///
/// The designed kid app was built in `kid_home_screen.dart` (initial
/// commit) complete with this tab bar. The "single-app-with-roles"
/// refactor then created a *second*, separate kid device app under
/// `lib/screens/kid/` and did not carry the navigation across — so
/// `kid_home_screen.dart` ended up reachable from exactly one place,
/// ParentDashboard's "Kid view" button. The parent could see the whole
/// kid experience; the kid got a single screen with no way out of it.
/// Tasks, Progress and Me were unreachable from the device they were
/// designed for.
///
/// This shell puts the navigation back on the kid's device and points
/// it at screens the kid is actually allowed to read (see below).
///
/// WHERE THE TAB BAR DOES *NOT* APPEAR
///
/// Only the free-time state gets tabs. LockedScreen, OnBreakScreen and
/// the "Approved. You're free." payoff stay full-screen:
///
///   - LockedScreen is the enforcement surface. Handing a locked kid a
///     nav bar out of it defeats the lock, and that screen already
///     carries the design's in-session task list and proof flow.
///   - OnBreakScreen is a countdown the kid should watch, not browse.
///   - The celebration is transient and self-dismissing.
class KidShell extends StatefulWidget {
  final String childName;

  /// Null only on kid_root's brief race-fallback path, before
  /// KidAuthService has finished restoring the kid's identity. The
  /// three data tabs need it, so they stay disabled until it arrives
  /// rather than rendering a screen that queries `child_id = null`.
  final String? childId;

  /// Clears the pairing. Surfaced through the settings gear so a
  /// paired device is never a dead end.
  final Future<void> Function()? onUnpair;

  const KidShell({
    super.key,
    required this.childName,
    this.childId,
    this.onUnpair,
  });

  @override
  State<KidShell> createState() => _KidShellState();
}

class _KidShellState extends State<KidShell> {
  int _index = 0;

  @override
  void didUpdateWidget(KidShell old) {
    super.didUpdateWidget(old);
    // If the child id arrives after first build the data tabs become
    // usable; if it goes away (unpair mid-session) fall back to Today
    // so we never leave the kid parked on a disabled tab.
    if (widget.childId == null && _index != 0) {
      setState(() => _index = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final childId = widget.childId;

    // IndexedStack keeps each tab's State alive, so switching tabs
    // doesn't re-run every screen's network read. The data tabs are
    // built lazily-ish: when childId is null they render a short
    // waiting note instead of querying with a null filter.
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(
                index: _index,
                children: [
                  KidTodayScreen(
                    childName: widget.childName,
                    childId: childId,
                    embedded: true,
                  ),
                  childId == null
                      ? const _GettingReady()
                      : KidTasksScreen(
                          childId: childId,
                          childName: widget.childName,
                        ),
                  childId == null
                      ? const _GettingReady()
                      : KidHistoryScreen(
                          childId: childId,
                          childName: widget.childName,
                          embedded: true,
                        ),
                  childId == null
                      ? const _GettingReady()
                      : KidMeScreen(
                          childId: childId,
                          childName: widget.childName,
                          onUnpair: widget.onUnpair,
                        ),
                ],
              ),
            ),
            if (widget.onUnpair != null)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: KidSettingsButton(
                    childName: widget.childName,
                    onUnpair: widget.onUnpair!,
                    color: AppColors.ink70,
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _tabBar(childId != null),
    );
  }

  Widget _tabBar(bool hasChild) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.borderCol)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: Row(
            children: [
              _tabItem(LucideIcons.house, 'Today', 0, true),
              _tabItem(LucideIcons.listChecks, 'Tasks', 1, hasChild),
              _tabItem(LucideIcons.trendingUp, 'Progress', 2, hasChild),
              _tabItem(LucideIcons.user, 'Me', 3, hasChild),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabItem(IconData icon, String label, int index, bool enabled) {
    final active = _index == index;
    final color = !enabled
        ? AppColors.inkFaint
        : active
        ? AppColors.green
        : AppColors.ink45;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled && !active ? () => setState(() => _index = index) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: AppText.caption().copyWith(
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in a data tab during the window where the kid is paired but
/// their child_id hasn't been restored yet. Deliberately says nothing
/// about their work — we don't know any of it yet.
class _GettingReady extends StatelessWidget {
  const _GettingReady();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.green,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Getting your stuff ready…',
              textAlign: TextAlign.center,
              style: AppText.bodySecondary(),
            ),
          ],
        ),
      ),
    );
  }
}
