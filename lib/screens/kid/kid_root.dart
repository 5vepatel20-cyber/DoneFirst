import 'package:flutter/material.dart';

import '../../../services/blocking_service.dart';
import '../../../services/heartbeat_service.dart';
import '../../../services/kid_auth_service.dart';
import '../../../services/kid_realtime_service.dart';
import '../../../services/kiosk_service.dart';
import '../../../theme/app_theme.dart';
import '../auth_screen.dart';
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
final KidRealtimeService realtime =
    KidRealtimeService(blocking: blocking, kiosk: kiosk);
final HeartbeatService heartbeat = HeartbeatService();

class KidRoot extends StatefulWidget {
  const KidRoot({super.key});

  @override
  State<KidRoot> createState() => _KidRootState();
}

class _KidRootState extends State<KidRoot> {
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
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    // kiosk.refreshDeviceOwner() is a single platform-channel call;
    // kidAuth.restoreSession() reads tokens from SharedPreferences +
    // calls Supabase.auth.recoverSession. Neither call depends on
    // the other — fire them in parallel so a slow platform-channel
    // hop doesn't delay session restore (or vice versa).
    bool restored = false;
    try {
      final results = await Future.wait<Object?>([
        kiosk.refreshDeviceOwner(),
        kidAuth.restoreSession(),
      ]);
      restored = results[1] as bool;
      if (restored && kidAuth.childId != null) {
        await realtime.start(kidAuth.childId!);
        heartbeat.start();
      }
    } catch (e) {
      // Without this catch the kid would see a stuck loading
      // screen forever with no feedback. The next call to setState
      // would also be skipped. We land on WaitingScreen so the kid
      // at least sees something actionable.
      debugPrint('KidRoot bootstrap failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Couldn’t start the kid app: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _signOut() async {
    await kidAuth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kidAuth.isPaired) {
      return PairingScreen(
        onSignOut: _signOut,
        authService: kidAuth,
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
                realtime.start(kidAuth.childId!);
              }
            },
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
        );
          }
          return LockedScreen(
            session: session,
            childName: _childDisplayName,
            onBreakRequestSent: () {},
          );
        }
        return OnBreakScreen(
          childName: _childDisplayName,
          activeBreak: brk,
        );
      case KidLockState.unlocked:
        return UnlockedScreen(
          childName: _childDisplayName,
          childId: kidAuth.childId,
        );
      case KidLockState.waiting:
        return WaitingScreen(
          onReconnect: () {
            if (kidAuth.childId != null) {
              realtime.start(kidAuth.childId!);
            }
          },
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
