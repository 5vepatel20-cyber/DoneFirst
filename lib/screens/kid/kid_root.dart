import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/blocking_service.dart';
import '../../../services/heartbeat_service.dart';
import '../../../services/kid_auth_service.dart';
import '../../../services/kid_realtime_service.dart';
import '../../../services/kiosk_service.dart';
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
  SharedPreferences? _prefs;

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
    _prefs = await SharedPreferences.getInstance();
    // Ask the native side whether we're the device owner. One-shot
    // at boot — device-owner status can't change at runtime without
    // an ADB command.
    await kiosk.refreshDeviceOwner();
    final restored = await kidAuth.restoreSession();
    if (restored && kidAuth.childId != null) {
      await realtime.start(kidAuth.childId!);
      heartbeat.start();
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
            return UnlockedScreen(childName: _childDisplayName);
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
        return UnlockedScreen(childName: _childDisplayName);
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
    final stored = _prefs?.getString('kid_display_name');
    if (stored != null && stored.isNotEmpty) return stored;
    return 'there';
  }
}
