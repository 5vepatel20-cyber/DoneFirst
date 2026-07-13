import 'package:flutter_test/flutter_test.dart';
import '../lib/services/kid_realtime_service.dart';

/// Tests for the realtime retry state machine.
///
/// The retry policy's job is to schedule a fresh subscribe() call
/// after the realtime channel reports anything other than
/// RealtimeSubscribeStatus.subscribed. Backoff doubles on each
/// consecutive failure, capped at 2 min, and the policy gives up
/// after 8 attempts (the WaitingScreen's heartbeat poll is the
/// fallback path that keeps the parent-side dot green while the
/// realtime channel is permanently broken).
void main() {
  group('RealtimeRetryPolicy', () {
    test('starts at 2s baseline', () {
      final p = RealtimeRetryPolicy();
      expect(p.current.inSeconds, 2);
      expect(p.attempts, 0);
      expect(p.shouldGiveUp, isFalse);
    });

    test('recordAttempt increments the counter', () {
      final p = RealtimeRetryPolicy();
      p.recordAttempt();
      expect(p.attempts, 1);
      p.recordAttempt();
      expect(p.attempts, 2);
    });

    test('bumpBackoff doubles up to 2 min cap', () {
      final p = RealtimeRetryPolicy();
      // 2 → 4 → 8 → 16 → 32 → 64 → 120 (capped) → 120 (still capped)
      p.bumpBackoff();
      expect(p.current.inSeconds, 4);
      p.bumpBackoff();
      expect(p.current.inSeconds, 8);
      p.bumpBackoff();
      expect(p.current.inSeconds, 16);
      p.bumpBackoff();
      expect(p.current.inSeconds, 32);
      p.bumpBackoff();
      expect(p.current.inSeconds, 64);
      p.bumpBackoff();
      expect(p.current.inSeconds, 120, reason: '7th bump caps at 2 min');
      p.bumpBackoff();
      expect(
        p.current.inSeconds,
        120,
        reason: '8th bump stays at the cap, not 240s',
      );
    });

    test('shouldGiveUp is true once attempts hit the limit', () {
      final p = RealtimeRetryPolicy();
      for (var i = 0; i < 8; i++) {
        expect(
          p.shouldGiveUp,
          isFalse,
          reason: 'attempt $i should not give up',
        );
        p.recordAttempt();
      }
      expect(p.shouldGiveUp, isTrue);
    });

    test('reset returns to the initial state', () {
      final p = RealtimeRetryPolicy();
      p.recordAttempt();
      p.recordAttempt();
      p.bumpBackoff();
      p.bumpBackoff();
      p.bumpBackoff();
      expect(p.current.inSeconds, 16);
      expect(p.attempts, 2);

      p.reset();
      expect(p.current.inSeconds, 2);
      expect(p.attempts, 0);
      expect(p.shouldGiveUp, isFalse);
    });

    test('reset clears give-up state', () {
      final p = RealtimeRetryPolicy();
      for (var i = 0; i < 8; i++) {
        p.recordAttempt();
      }
      expect(p.shouldGiveUp, isTrue);

      p.reset();
      expect(p.shouldGiveUp, isFalse);
    });
  });
}
