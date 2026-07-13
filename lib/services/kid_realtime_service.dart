import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'blocking_service.dart';
import 'kiosk_service.dart';

/// Retry policy for the realtime subscription.
///
/// Supabase realtime has its own internal reconnect on transient
/// blips (WiFi flapping, brief TCP timeout). This is the second
/// line of defense: if subscribe() itself never transitions to
/// [RealtimeSubscribeStatus.subscribed], we tear the channel down
/// and rebuild it after a backoff. This catches the case where the
/// kid app launches with no network and supabase's internal retry
/// gives up.
class RealtimeRetryPolicy {
  static const Duration _base = Duration(seconds: 2);
  static const Duration _max = Duration(minutes: 2);

  /// Maximum retries before we give up and stay on the Waiting
  /// screen indefinitely. After this many, the user has to
  /// manually reconnect (the WaitingScreen polls heartbeat
  /// every 5s, which keeps the parent-side dot green even when
  /// the realtime channel can't recover).
  static const int _maxAttempts = 8;

  Duration _current = _base;
  int _attempts = 0;

  Duration get current => _current;
  int get attempts => _attempts;
  int get maxAttempts => _maxAttempts;

  void recordAttempt() {
    _attempts++;
  }

  bool get shouldGiveUp => _attempts >= _maxAttempts;

  void bumpBackoff() {
    final next = _current.inMilliseconds * 2;
    _current = next > _max.inMilliseconds ? _max : Duration(milliseconds: next);
  }

  void reset() {
    _current = _base;
    _attempts = 0;
  }
}

/// Top-level lock state for the kid UI.
///
/// The kid app is much simpler than the parent: it doesn't track
/// tasks, proofs, break request lists, etc. — it only cares about
/// "am I locked right now, and if so why?".
enum KidLockState {
  /// No active session. Shows the Unlocked screen.
  unlocked,

  /// Active session with no special conditions. Shows the Locked
  /// screen with a countdown to the session's natural end.
  locked,

  /// Session exists but the realtime channel is currently
  /// disconnected (WiFi drop, etc). Releases the lock immediately
  /// — better to give the kid their apps than to leave them stuck
  /// behind a non-responding OS lock.
  waiting,
}

/// Event emitted to listeners (mainly [main.dart] which swaps the
/// screen based on state).
class KidLockEvent {
  final KidLockState state;
  final HomeworkSessionPayload? session;
  final bool isRealtimeHealthy;

  const KidLockEvent({
    required this.state,
    this.session,
    required this.isRealtimeHealthy,
  });
}

/// Parsed subset of homework_sessions the kid cares about. We don't
/// reuse the parent app's HomeworkSession model because the kid app
/// doesn't need tasks/proofs/parent_id etc.
class HomeworkSessionPayload {
  final String id;
  final String childId;
  final String status; // 'active' | 'paused' | 'completed' | 'cancelled'
  final int minLockMinutes;
  final DateTime startedAt;
  final DateTime? endedAt;

  const HomeworkSessionPayload({
    required this.id,
    required this.childId,
    required this.status,
    required this.minLockMinutes,
    required this.startedAt,
    this.endedAt,
  });

  factory HomeworkSessionPayload.fromMap(Map<String, dynamic> map) =>
      HomeworkSessionPayload(
        id: map['id'] as String,
        childId: map['child_id'] as String,
        status: (map['status'] as String?) ?? 'active',
        // PG bigint → num → int
        minLockMinutes: (map['min_lock_minutes'] as num?)?.toInt() ?? 0,
        startedAt:
            DateTime.tryParse(map['started_at']?.toString() ?? '') ??
            DateTime.now(),
        endedAt: DateTime.tryParse(map['ended_at']?.toString() ?? ''),
      );
}

/// Subscribes to homework_sessions for the signed-in kid device and
/// drives the [BlockingService] + the UI state machine.
///
/// The subscription filter uses a Postgres `eq` filter on child_id,
/// which is RLS-respected server-side. The kid JWT's app_metadata
/// carries child_id (see KidAuthService.claimPairingCode) so RLS
/// permits rows where child_id = auth.jwt() -> 'app_metadata' ->>
/// 'child_id'.
class KidRealtimeService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  final BlockingService blocking;
  final KioskService kiosk;
  final RealtimeRetryPolicy _retryPolicy;

  KidLockState _state = KidLockState.unlocked;
  HomeworkSessionPayload? _session;
  bool _isHealthy = false;

  KidLockState get state => _state;
  HomeworkSessionPayload? get session => _session;
  bool get isRealtimeHealthy => _isHealthy;

  /// Current retry state. Exposed for tests.
  RealtimeRetryPolicy get retryPolicy => _retryPolicy;

  RealtimeChannel? _channel;
  StreamSubscription? _sub;
  String? _childId;
  Timer? _retryTimer;

  KidRealtimeService({
    required this.blocking,
    required this.kiosk,
    RealtimeRetryPolicy? retryPolicy,
  }) : _retryPolicy = retryPolicy ?? RealtimeRetryPolicy();

  /// Start listening for the given child. Idempotent — calling
  /// twice with the same childId does nothing.
  Future<void> start(String childId) async {
    if (_channel != null && _childId == childId) return;
    await stop();
    _childId = childId;
    _retryPolicy.reset();

    // Bootstrap by reading the latest session state once. Realtime
    // only delivers changes — if there's already an active session
    // when the kid app launches (e.g. parent started it before
    // pairing completed, or kid app is being relaunched after the
    // lock was already in progress), we need to learn about it.
    await _loadInitial(childId);

    _subscribe();
  }

  void _subscribe() {
    final childId = _childId;
    if (childId == null) return;
    _retryPolicy.recordAttempt();
    _channel = _supabase.channel('kid_homework_$childId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'homework_sessions',
        // PostgREST filter — only rows where child_id matches.
        // The .eq filter is applied server-side; rows for other
        // children never reach us.
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'child_id',
          value: childId,
        ),
        callback: _onChange,
      ).subscribe(_onSubscribe);
  }

  Future<void> stop() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _supabase.removeChannel(_channel!);
    _channel = null;
    _isHealthy = false;
    _childId = null;
    _retryPolicy.reset();
    // Don't release the blocking here unconditionally — the
    // Locked/Unlocked screen swap may not have happened yet. The
    // caller decides via `releaseLockIfAny`.
    notifyListeners();
  }

  /// Release any active blocking. Call from WaitingScreen / on
  /// signOut to make sure the kid doesn't get stuck behind the
  /// plugin block when the realtime channel goes away.
  Future<void> releaseLockIfAny() async {
    if (blocking.isBlocking) {
      await blocking.stopBlocking();
    }
    if (kiosk.isLocked) {
      await kiosk.stopLockTask();
    }
  }

  Future<void> _loadInitial(String childId) async {
    try {
      final response = await _supabase
          .from('homework_sessions')
          .select(
            'id, child_id, status, min_lock_minutes, '
            'started_at, ended_at',
          )
          .eq('child_id', childId)
          .eq('status', 'active')
          .order('started_at', ascending: false)
          .limit(1);
      if (response.isNotEmpty) {
        final payload = HomeworkSessionPayload.fromMap(response.first);
        _applySession(payload);
      } else {
        _applySession(null);
      }
    } catch (e) {
      debugPrint('KidRealtimeService initial load error: $e');
      // Fail open: treat as waiting so the UI doesn't show a
      // stale "Locked" state from before the load failed.
      _state = KidLockState.waiting;
      _isHealthy = false;
      await releaseLockIfAny();
      notifyListeners();
    }
  }

  void _onSubscribe(RealtimeSubscribeStatus status, Object? error) {
    // Supabase realtime status: subscribed / channelError / closed /
    // timedOut. We only treat subscribed as healthy; everything
    // else flips the UI to KidLockState.waiting and releases the
    // lock so the kid isn't trapped.
    final wasHealthy = _isHealthy;
    _isHealthy = status == RealtimeSubscribeStatus.subscribed;
    if (error != null) {
      debugPrint('Realtime subscribe error: $error');
    }
    if (_isHealthy) {
      // Success — reset retry state and cancel any pending retry.
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryPolicy.reset();
    } else if (wasHealthy && !_isHealthy) {
      // We were subscribed and now we're not. This is a runtime
      // drop (server restart, network blip). Schedule a retry —
      // supabase's internal reconnection will probably beat us,
      // but if not, we'll rebuild the channel from scratch.
      _scheduleRetry();
    }
    // First-subscribe failure (wasHealthy==false and never healthy)
    // is handled by the caller of _subscribe() — we don't want to
    // double-schedule.
    _recomputeState();
    notifyListeners();
  }

  void _scheduleRetry() {
    if (_retryPolicy.shouldGiveUp) {
      debugPrint(
        'Realtime retry policy exhausted '
        '(${_retryPolicy.attempts} attempts); staying in waiting',
      );
      return;
    }
    _retryTimer?.cancel();
    final delay = _retryPolicy.current;
    debugPrint(
      'Realtime retry in ${delay.inSeconds}s '
      '(attempt ${_retryPolicy.attempts})',
    );
    _retryTimer = Timer(delay, () async {
      if (_childId == null) return;
      // Tear down the broken channel and resubscribe.
      try {
        await _supabase.removeChannel(_channel!);
      } catch (_) {
        /* best-effort */
      }
      _channel = null;
      _retryPolicy.bumpBackoff();
      _subscribe();
    });
  }

  void _onChange(PostgresChangePayload payload) {
    final newRow = payload.newRecord;
    if (newRow.isEmpty) {
      // DELETE — no longer any active session for this child.
      _applySession(null);
      return;
    }
    final parsed = HomeworkSessionPayload.fromMap(newRow);
    _applySession(parsed);
  }

  void _applySession(HomeworkSessionPayload? session) {
    _session = session;
    _recomputeState();
    _enforce();
    notifyListeners();
  }

  /// Decide which UI state to show + start/stop the block plugin
  /// AND the OS-level kiosk lock.
  ///
  /// Rules:
  ///   - realtime unhealthy → waiting (release any active block).
  ///   - session missing → unlocked (release any active block).
  ///   - session.status != 'active' → unlocked (release).
  ///   - else → locked (start block + kiosk lock-task).
  Future<void> _enforce() async {
    final shouldBeLocked = _state == KidLockState.locked;
    if (shouldBeLocked) {
      if (!blocking.isBlocking) {
        final ok = await blocking.startBlocking();
        if (!ok) {
          // Permission denied or plugin threw — surface as waiting
          // so the kid UI shows the actionable "allow UsageStats
          // access" path instead of a frozen Locked screen with no
          // countdown ticking.
          _state = KidLockState.waiting;
          notifyListeners();
          return;
        }
      }
      if (!kiosk.isLocked) {
        // Start OS-level kiosk lock. If we're not the device owner,
        // this is a no-op and isLocked stays false — but the app
        // block above is still in force, so the kid can't actually
        // use other apps. The visible UI just won't have the
        // home-button lockout.
        await kiosk.startLockTask();
      }
    } else {
      if (blocking.isBlocking) {
        await blocking.stopBlocking();
      }
      if (kiosk.isLocked) {
        await kiosk.stopLockTask();
      }
    }
  }

  void _recomputeState() {
    if (!_isHealthy) {
      _state = KidLockState.waiting;
      return;
    }
    final s = _session;
    if (s == null) {
      _state = KidLockState.unlocked;
      return;
    }
    if (s.status == 'active') {
      _state = KidLockState.locked;
    } else {
      // 'paused' / 'completed' / 'cancelled' — kid is free.
      _state = KidLockState.unlocked;
    }
  }
}
