import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/blocking_service.dart';
import '../../../services/heartbeat_service.dart';
import '../../../services/kid_auth_service.dart';
import '../../../services/kid_realtime_service.dart';
import '../../../services/kiosk_service.dart';
import '../../../theme/app_theme.dart';
import '../auth_screen.dart';
import '../splash_screen.dart';
import 'kid_shell.dart';
import 'locked_screen.dart';
import 'on_break_screen.dart';
import 'pairing_screen.dart';
import 'unlocked_screen.dart';
import 'waiting_screen.dart';

/// Single-app-with-roles container: when this widget mounts the
/// app has already detected the user's role is 'kid' (see main.dart
/// routing). It still owns its own boot logic because kids bypass
/// the parent auth flow entirely — they come here directly from
/// RoleSelectScreen and need to claim a pairing code.
///
/// Mirrors the kid app's old _RootRouter but lives inside the parent
/// project so the same APK supports both modes.
final KidAuthService kidAuth = KidAuthService();
final BlockingService blocking = BlockingService();
final KioskService kiosk = KioskService();
final KidRealtimeService realtime = KidRealtimeService(
  blocking: blocking,
  kiosk: kiosk,
  // Realtime must authenticate as the kid even when setSession
  // failed on web — feed it the persisted-token fallback so the
  // homework_sessions subscription passes RLS.
  tokenProvider: kidAuth.getAccessToken,
);
final HeartbeatService heartbeat = HeartbeatService(kidAuth: kidAuth);

class KidRoot extends StatefulWidget {
  const KidRoot({super.key});

  @override
  State<KidRoot> createState() => _KidRootState();
}

class _KidRootState extends State<KidRoot> {
  /// True until [_bootstrap] finishes. Without it the first build
  /// runs while kidAuth.isPaired is still false and an already-paired
  /// kid sees a flash of PairingScreen. On web that window is
  /// seconds, not a frame: restoreSession has to wait out two
  /// setSession round-trips before the persisted-JWT fallback kicks
  /// in, which is long enough for a kid to start typing a code into
  /// a screen that's about to be yanked away.
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // The router rebuilds whenever auth or realtime state changes.
    kidAuth.addListener(_onChange);
    realtime.addListener(_onChange);
  }

  @override
  void dispose() {
    kidAuth.removeListener(_onChange);
    realtime.removeListener(_onChange);
    _celebrationTimer?.cancel();
    super.dispose();
  }

  /// Auto-dismisses the "Approved. You're free." payoff.
  Timer? _celebrationTimer;

  /// Long enough to read the headline and the three stat tiles and
  /// feel rewarded; short enough that a kid who wanders off and comes
  /// back finds their dashboard rather than a stale trophy.
  static const Duration _celebrationDuration = Duration(seconds: 45);

  /// Called from build, so it must be idempotent: an already-armed
  /// timer is left alone rather than restarted, otherwise every
  /// rebuild (the stats fetch alone triggers several) would push the
  /// deadline out and the celebration would never end.
  void _armCelebrationTimeout() {
    if (_celebrationTimer?.isActive ?? false) return;
    _celebrationTimer = Timer(_celebrationDuration, () {
      if (mounted) realtime.dismissFinishedSession();
    });
  }

  /// child_id the background services are running for. Guards
  /// [_ensureServicesStarted] against re-entry — kidAuth and realtime
  /// both notify on every state change, so this runs constantly.
  String? _servicesStartedFor;

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    // A kid who *just* paired arrives here, not through _bootstrap.
    _ensureServicesStarted();
  }

  /// Start realtime + heartbeat for the paired kid if they aren't
  /// already running.
  ///
  /// Pairing finishes inside PairingScreen, which only claims the
  /// code — it deliberately doesn't navigate, it just lets kidAuth
  /// notify so this router rebuilds. But _bootstrap ran minutes ago
  /// and was the only thing that ever called realtime.start(), so a
  /// freshly-paired kid rebuilt straight into `KidLockState.waiting`
  /// — "Can't reach the parent app" — and sat there until they
  /// relaunched the app or found the reconnect button. Starting the
  /// services here closes that gap: pairing lands on the Today
  /// dashboard the way an already-paired launch does.
  Future<void> _ensureServicesStarted() async {
    final childId = kidAuth.childId;
    if (childId == null || _servicesStartedFor == childId) return;
    // Claim before the await so a burst of notifications can't fire
    // several concurrent starts.
    _servicesStartedFor = childId;
    try {
      // Bounded: start() does a network read and a socket handshake,
      // and a hung one would latch the guard above forever — no later
      // notification would ever retry, leaving a paired kid on the
      // waiting screen for good.
      await realtime.start(childId).timeout(const Duration(seconds: 20));
      heartbeat.start();
    } catch (e) {
      // Let the next notification (or the waiting screen's 5s nudge)
      // retry rather than latching a half-started state.
      _servicesStartedFor = null;
      debugPrint('KidRoot: starting services for $childId failed: $e');
    }
  }

  Future<void> _bootstrap() async {
    // kiosk.refreshDeviceOwner() is a single platform-channel call;
    // kidAuth.restoreSession() reads tokens from SharedPreferences +
    // calls Supabase.auth.recoverSession. Neither call depends on
    // the other — fire them in parallel so a slow platform-channel
    // hop doesn't delay session restore (or vice versa).
    bool restored = false;
    try {
      // Bounded. Everything inside is *supposed* to be bounded already
      // — restoreSession caps its two setSession attempts, and the
      // platform channel either answers or throws MissingPluginException
      // — but _booting gates the entire kid UI behind a splash with no
      // text and no controls, so anything that doesn't return here
      // leaves a kid staring at a logo with no way forward. A ceiling
      // here means the worst case is the pairing screen, which is at
      // least a screen they can act on. The catch below handles it.
      final results = await Future.wait<Object?>([
        kiosk.refreshDeviceOwner(),
        kidAuth.restoreSession(),
      ]).timeout(const Duration(seconds: 40));
      restored = results[1] as bool;
      // Render the moment we know whether this device is paired.
      // Subscribing to realtime takes a REST read plus a socket
      // handshake — seconds on a good network, forever on a stalled
      // one — and the router already has an honest screen for
      // "paired, realtime hasn't reported yet". Holding the splash
      // until the subscription lands turned a slow network into an
      // app that never finishes launching.
      if (mounted) setState(() => _booting = false);
      if (restored) unawaited(_ensureServicesStarted());
    } catch (e) {
      // Without this catch the kid would see a stuck loading
      // screen forever with no feedback. The next call to setState
      // would also be skipped. We land on WaitingScreen so the kid
      // at least sees something actionable.
      debugPrint('KidRoot bootstrap failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Couldn’t start the kid app: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      // Always clear the boot flag — a bootstrap that threw still
      // has to render something, and the routing below already
      // handles the not-paired / no-realtime-state cases.
      if (mounted) setState(() => _booting = false);
    }
  }

  Future<void> _signOut() async {
    await kidAuth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  /// Unpair from within the app (settings sheet). Unlike [_signOut]
  /// we don't push AuthScreen — clearing the session flips
  /// kidAuth.isPaired to false and the listener rebuilds this widget
  /// straight to the PairingScreen. Stop the background services
  /// first so a stale channel/heartbeat doesn't linger post-unpair.
  Future<void> _unpair() async {
    await realtime.stop();
    heartbeat.stop();
    // Re-arm the start guard, or pairing this device to a sibling
    // right afterwards would never bring the services back up.
    _servicesStartedFor = null;
    await kidAuth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      // Brand splash, not PairingScreen — we don't yet know whether
      // this device is paired, and guessing wrong in either
      // direction shows the kid a screen that then swaps under them.
      return const SplashScreen();
    }
    if (!kidAuth.isPaired) {
      return PairingScreen(onSignOut: _signOut, authService: kidAuth);
    }
    if (!kidAuth.hasLiveSession) {
      // Paired, but the Supabase client has no kid session, so every
      // read is going out as anon and coming back empty — with a 200,
      // not an error. Rendering the dashboard here would show a kid
      // who studied all week 0m / 0 sessions / 0 streak and tell them
      // nothing is scheduled, and rendering `unlocked` would release
      // a lock we simply cannot see. WaitingScreen is the honest
      // answer: it says we can't reach the parent app, offers
      // reconnect, and keeps the settings gear so the device can be
      // re-paired if the session is gone for good.
      return WaitingScreen(
        reason: KidWaitingReason.disconnected,
        onReconnect: () {
          if (kidAuth.childId != null) {
            realtime.reconnect(kidAuth.childId!);
          }
        },
        heartbeat: heartbeat,
        childName: _childDisplayName,
        onUnpair: _unpair,
      );
    }
    // Realtime drives the lock state. Fall back to waiting if it
    // hasn't reported anything yet — most commonly because the
    // bootstrap above hasn't finished subscribing.
    switch (realtime.state) {
      case KidLockState.locked:
        final session = realtime.session;
        if (session == null) {
          // Race: state says locked but session payload hasn't
          // arrived yet. Render waiting rather than crashing.
          return WaitingScreen(
            onReconnect: () {
              if (kidAuth.childId != null) {
                realtime.reconnect(kidAuth.childId!);
              }
            },
            heartbeat: heartbeat,
            childName: _childDisplayName,
            onUnpair: _unpair,
          );
        }
        return LockedScreen(
          session: session,
          childName: _childDisplayName,
          onBreakRequestSent: () {},
        );
      case KidLockState.onBreak:
        // Active session + a parent-approved break in flight.
        // Same enforcement as unlocked (no app block, no kiosk
        // lock) but the UI explains the kid is on a break rather
        // than fully free — a fully free kid with an active
        // session would be confusing.
        final brk = realtime.activeBreak;
        if (brk == null) {
          // Race: state says onBreak but the break payload
          // hasn't arrived yet. Fall through to LockedScreen
          // with whatever session we have; the realtime event
          // will reconcile within a tick.
          final session = realtime.session;
          if (session == null) {
            return UnlockedScreen(
              childName: _childDisplayName,
              childId: kidAuth.childId,
              onUnpair: _unpair,
              celebrate: realtime.justFinishedSession,
            );
          }
          return LockedScreen(
            session: session,
            childName: _childDisplayName,
            onBreakRequestSent: () {},
          );
        }
        return OnBreakScreen(childName: _childDisplayName, activeBreak: brk);
      case KidLockState.unlocked:
        // Two very different situations share this state. Right after a
        // session ends, `justFinishedSession` is true → the transient
        // "Approved. You're free." payoff (UnlockedScreen). Otherwise
        // the kid is simply free — no session running — and lands on
        // their Today dashboard (greeting, streak, next session,
        // today's focus), the redesign's "Kid · Today" home.
        if (realtime.justFinishedSession) {
          // Transient by design — see _armCelebrationTimeout. Without
          // the timeout (and the tap-out below) this screen was a
          // dead end: the flag only cleared when the *next* session
          // began, so finishing homework cost the kid their dashboard
          // until the app was relaunched.
          _armCelebrationTimeout();
          return UnlockedScreen(
            childName: _childDisplayName,
            childId: kidAuth.childId,
            onUnpair: _unpair,
            celebrate: true,
            onDone: realtime.dismissFinishedSession,
          );
        }
        // The free-time home, with the redesign's four-tab bar. Only
        // this state gets tabs — see KidShell for why locked, on-break
        // and the celebration deliberately stay full-screen.
        return KidShell(
          childName: _childDisplayName,
          childId: kidAuth.childId,
          onUnpair: _unpair,
        );
      case KidLockState.waiting:
        return WaitingScreen(
          onReconnect: () {
            if (kidAuth.childId != null) {
              realtime.reconnect(kidAuth.childId!);
            }
          },
          heartbeat: heartbeat,
          childName: _childDisplayName,
          onUnpair: _unpair,
        );
    }
  }

  String get _childDisplayName {
    // Populated by KidAuthService.claimPairingCode from the
    // edge function's child_name field, and re-read from
    // SharedPreferences on restoreSession so a cold launch can
    // still greet the kid by name without re-pairing.
    final name = kidAuth.childName;
    if (name != null && name.isNotEmpty) return name;
    return 'there';
  }
}
