import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// Liveness signal back to the parent app.
///
/// Posts to the heartbeat edge function which updates
/// `kid_devices.last_seen_at`. The parent app's KidDeviceService
/// computes (now - last_seen_at > 90s) → device is offline and
/// the status dot turns gray.
///
/// Cadence:
///   - Baseline 30s when the network is healthy.
///   - Exponential backoff up to 5 min on consecutive failures.
///   - Reset to 30s on the next successful post.
///
/// Why 30s baseline and not 90s: if we posted every 90s the parent
/// would see the device as offline for up to 90s after the kid
/// actually dropped off. 30s gives the parent < 30s of false-offline
/// window without spamming the server.
///
/// Why backoff: a flaky WiFi connection shouldn't trigger 12 retries
/// in 6 minutes, hammering the edge function and burning the kid's
/// battery. 30s → 60s → 120s → 240s → 300s (capped) gives the
/// network time to recover while still signaling offline status
/// promptly on the parent side.
///
/// Why not realtime alone: realtime subscriptions can silently drop
/// without disconnecting (e.g. background TCP timeout). The parent
/// needs a positive signal, not just "still subscribed".
class HeartbeatService {
  /// Baseline cadence — used after every successful post.
  static const Duration _baseInterval = Duration(seconds: 30);

  /// Maximum backoff between attempts. Capped so a parent whose
  /// kid's network is broken for a day still gets a green-dot
  /// signal the moment it recovers (within 5 min).
  static const Duration _maxInterval = Duration(minutes: 5);

  /// Per-request timeout. Anything slower than this and we treat
  /// it as a network failure and back off.
  static const Duration _requestTimeout = Duration(seconds: 10);

  final _supabase = Supabase.instance.client;
  Timer? _timer;
  Duration _currentInterval = _baseInterval;
  bool _running = false;
  bool get isRunning => _running;

  /// Current backoff interval. Exposed for tests; the UI doesn't
  /// read this directly (the parent computes offline status from
  /// last_seen_at alone).
  Duration get currentInterval => _currentInterval;

  /// Start the periodic heartbeat. Idempotent — calling twice
  /// does nothing.
  void start() {
    if (_timer != null) return;
    _running = true;
    _currentInterval = _baseInterval;
    // Fire one immediately so the parent sees us right after
    // pairing, then schedule the next tick.
    unawaited(_send());
    _scheduleNext();
  }

  /// Stop the heartbeat. Used when the kid app is being torn down
  /// (sign out) or when the server revokes the device (401).
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _send() async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      // Not paired yet — silently no-op. The pairing screen will
      // start the heartbeat once it completes.
      return;
    }
    final access = session.accessToken;
    final url = Uri.parse('$supabaseUrl/functions/v1/heartbeat');
    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $access',
              'apikey': supabaseAnonKey,
            },
          )
          .timeout(_requestTimeout);
      if (response.statusCode == 401) {
        // Device was revoked between heartbeats — stop the timer
        // so we don't keep hitting a 401 forever. The realtime
        // subscription will also fail; the WaitingScreen handles
        // that path.
        stop();
        return;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        recordSuccess();
      } else {
        debugPrint(
          'heartbeat non-2xx: ${response.statusCode} '
          '${response.body}',
        );
        recordFailure();
      }
    } on TimeoutException {
      debugPrint('heartbeat timeout');
      recordFailure();
    } catch (e) {
      // Network blip — don't surface to the kid. Worst case the
      // parent sees the dot turn gray for one window, then back to
      // green on the next successful post.
      debugPrint('heartbeat error: $e');
      recordFailure();
    }
  }

  /// Mark the last heartbeat attempt as successful. Resets the
  /// backoff interval to baseline. Exposed for the WaitingScreen
  /// (which calls sendOnce when reconnecting) and for tests.
  void recordSuccess() {
    _currentInterval = _baseInterval;
  }

  /// Mark the last heartbeat attempt as failed. Doubles the
  /// backoff interval up to [_maxInterval]. Exposed for tests.
  void recordFailure() {
    final nextMs = _currentInterval.inMilliseconds * 2;
    final cappedMs = nextMs > _maxInterval.inMilliseconds
        ? _maxInterval.inMilliseconds
        : nextMs;
    _currentInterval = Duration(milliseconds: cappedMs);
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_currentInterval, () async {
      await _send();
      if (_running) {
        _scheduleNext();
      }
    });
  }

  /// Manual one-shot. Useful for tests or for the kid-side
  /// "Reconnecting" state which wants to immediately tell the
  /// parent "we're back" rather than wait up to 30s for the next tick.
  Future<void> sendOnce() => _send();
}
