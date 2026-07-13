import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Device pairing + management for the parent side of DoneFirst.
/// The single-app refactor collapses the kid-side companion into
/// this same Flutter project — the parent still calls all the
/// pairing/revoke/list endpoints here, the kid calls claim-pairing
/// via the Edge Function in `supabase/functions/claim-pairing/`.
///
/// All operations are scoped to the parent's family via RLS:
///   - `device_pairings` (Migration 11): parent can SELECT / INSERT
///     / DELETE for their family.
///   - `kid_devices` (Migration 11 + 13): parent can SELECT and
///     UPDATE (revoke) for their family. Inserts happen via the
///     service-role Edge Function on claim.
class KidDeviceService {
  final _supabase = Supabase.instance.client;

  /// Generates a fresh 6-digit pairing code for the given child.
  /// The code is single-use and expires 10 minutes after creation.
  /// Returns the code + the database row id (so the UI can poll for
  /// claim status if it wants to).
  ///
  /// Codes are generated client-side using crypto-secure randomness
  /// rather than a server sequence so we don't need a new Edge
  /// Function just to mint them. The 6-digit space (1M) plus the
  /// 10-min expiry caps brute force at ~1667 attempts/sec — well
  /// under Supabase's per-IP limit.
  Future<GeneratedPairingCode> generatePairingCode({
    required String childId,
    Duration validFor = const Duration(minutes: 10),
  }) async {
    final code = _generateSixDigitCode();
    final expiresAt = DateTime.now().add(validFor);
    final userId = _supabase.auth.currentUser!.id;

    // Resolve the parent's family_id. We need it because the
    // device_pairings INSERT requires the row to belong to a family
    // the parent is in (RLS check).
    final parent = await _supabase
        .from('parents')
        .select('family_id')
        .eq('id', userId)
        .single();
    final familyId = parent['family_id'] as String?;

    // Edge case: a parent who hasn't created/joined a family yet.
    // RLS won't let us insert without a family_id. Bubble a clear
    // error so the UI can prompt the parent to set up a family
    // first (which is required for everything else too).
    if (familyId == null) {
      throw KidDeviceException(
        'Set up your family before pairing a kid device. '
        'Add a child first.',
        code: 'NO_FAMILY',
      );
    }

    try {
      final inserted = await _supabase
          .from('device_pairings')
          .insert({
            'code': code,
            'family_id': familyId,
            'child_id': childId,
            'created_by': userId,
            'expires_at': expiresAt.toIso8601String(),
          })
          .select('code, expires_at')
          .single();
      return GeneratedPairingCode(
        code: inserted['code'] as String,
        expiresAt: DateTime.parse(inserted['expires_at'] as String),
      );
    } on PostgrestException catch (e) {
      // Most likely: unique-constraint violation on the code (we
      // happened to roll the same 6 digits twice in a row, ~1/M
      // odds). Retry once with a fresh roll; if it still fails,
      // bubble the error.
      if (e.code == '23505') {
        final retryCode = _generateSixDigitCode();
        final retry = await _supabase
            .from('device_pairings')
            .insert({
              'code': retryCode,
              'family_id': familyId,
              'child_id': childId,
              'created_by': userId,
              'expires_at': expiresAt.toIso8601String(),
            })
            .select('code, expires_at')
            .single();
        return GeneratedPairingCode(
          code: retry['code'] as String,
          expiresAt: DateTime.parse(retry['expires_at'] as String),
        );
      }
      rethrow;
    }
  }

  /// Lists the parent's family kid devices, ordered by last-seen
  /// (most recent first). Revoked devices are included at the end
  /// so the parent can see the audit trail but UI can grey them out.
  Future<List<KidDevice>> listFamilyDevices() async {
    final rows = await _supabase
        .from('kid_devices_with_child')
        .select()
        .order('last_seen_at', ascending: false, nullsFirst: false);

    return rows
        .map((r) => KidDevice.fromMap(r))
        .toList(growable: false);
  }

  /// Lists devices paired to a single child. Used by the per-child
  /// popup-menu path on the dashboard.
  Future<List<KidDevice>> listDevicesForChild(String childId) async {
    final rows = await _supabase
        .from('kid_devices_with_child')
        .select()
        .eq('child_id', childId)
        .order('last_seen_at', ascending: false, nullsFirst: false);

    return rows
        .map((r) => KidDevice.fromMap(r))
        .toList(growable: false);
  }

  /// Revokes a paired kid device. Sets `revoked_at = now()` on the
  /// row. The kid's auth user keeps existing (we don't delete it —
  /// that would let a determined kid re-pair to a stale account)
  /// but the JWT will be rejected on the next heartbeat because
  /// claim-pairing checks the device's claimed_by_device reference
  /// and we'd reject the kid session re-restore.
  ///
  /// Actually simpler: the heartbeat edge function checks if the
  /// kid_devices row has revoked_at set; if so, returns 401 and the
  /// kid app flips to WaitingScreen. We don't need to touch the
  /// auth user.
  Future<void> revokeDevice(String deviceId) async {
    await _supabase
        .from('kid_devices')
        .update({'revoked_at': DateTime.now().toIso8601String()})
        .eq('id', deviceId);
  }

  /// Updates the user-friendly label for a paired kid device. The
  /// kid app submits a default name on pairing (e.g. "Pixel 8")
  /// but parents often want to rename to something more useful
  /// like "Bedroom tablet" or "School iPad". Pass null/empty to
  /// clear the override and fall back to the kid-side default.
  ///
  /// RLS keeps this scoped to the parent's family — a co-parent
  /// can't rename another family's device.
  Future<void> renameDevice(String deviceId, String? newName) async {
    final trimmed = newName?.trim();
    await _supabase
        .from('kid_devices')
        .update({
          'device_name': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        })
        .eq('id', deviceId);
  }

  /// Cancels an unused pairing code (parent changed their mind).
  /// Codes that have been claimed can't be deleted this way — the
  /// kid_devices row stays, and the parent can revoke that instead.
  Future<void> cancelPairingCode(String code) async {
    await _supabase
        .from('device_pairings')
        .delete()
        .eq('code', code)
        .isFilter('claimed_at', null);
  }

  /// Generates a 6-digit numeric string with leading zeros preserved
  /// (e.g. "004271", not just "4271"). Uses `Random.secure` for
  /// cryptographic randomness — a non-secure RNG here would let a
  /// kid guess upcoming codes by observing their own.
  static String _generateSixDigitCode() {
    final rng = Random.secure();
    final n = rng.nextInt(1000000);
    return n.toString().padLeft(6, '0');
  }
}

/// Returned by [KidDeviceService.generatePairingCode]. The UI
/// shows the code + a countdown to `expiresAt`. The DB row id is
/// not exposed — callers don't need it.
class GeneratedPairingCode {
  final String code;
  final DateTime expiresAt;

  const GeneratedPairingCode({
    required this.code,
    required this.expiresAt,
  });

  /// Whether the code has expired (compared to wall-clock now). The
  /// server-side check is authoritative — the kid app's call to
  /// claim-pairing rejects expired codes regardless of what this
  /// returns. This is just for the UI countdown.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeUntilExpiry => expiresAt.difference(DateTime.now());
}

/// One row of the `kid_devices_with_child` view. Field names match
/// the view columns; `status` is the derived 'online'/'recent'/
/// 'stale'/'unknown'/'revoked' enum.
class KidDevice {
  final String id;
  final String familyId;
  final String childId;
  final String? childDisplayName;
  final String? deviceName;
  final DateTime pairedAt;
  final DateTime? lastSeenAt;
  final DateTime? revokedAt;
  final String status;

  const KidDevice({
    required this.id,
    required this.familyId,
    required this.childId,
    required this.childDisplayName,
    required this.deviceName,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.revokedAt,
    required this.status,
  });

  factory KidDevice.fromMap(Map<String, dynamic> map) => KidDevice(
        id: map['id'] as String,
        familyId: map['family_id'] as String,
        childId: map['child_id'] as String,
        childDisplayName: map['child_display_name'] as String?,
        deviceName: map['device_name'] as String?,
        pairedAt: DateTime.parse(map['paired_at'] as String),
        lastSeenAt: map['last_seen_at'] == null
            ? null
            : DateTime.parse(map['last_seen_at'] as String),
        revokedAt: map['revoked_at'] == null
            ? null
            : DateTime.parse(map['revoked_at'] as String),
        status: map['status'] as String,
      );

  /// Human-readable "last seen" string for the UI ("just now",
  /// "12 min ago", "2 days ago"). Returns "—" for devices that
  /// never reported a heartbeat (paired but never online, or
  /// revoked before first heartbeat).
  String lastSeenLabel(DateTime now) {
    if (lastSeenAt == null) return 'Never';
    final delta = now.difference(lastSeenAt!);
    if (delta.inSeconds < 30) return 'Just now';
    if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }

  bool get isRevoked => revokedAt != null;
  bool get isOnline => status == 'online';
}

/// Typed exception so the UI can show targeted error copy without
/// string-matching on Postgres error messages.
class KidDeviceException implements Exception {
  final String message;
  final String code;

  const KidDeviceException(this.message, {required this.code});

  @override
  String toString() => 'KidDeviceException($code): $message';
}

/// Read-only service for the kid_device_events_with_context view.
/// Events themselves are inserted by Postgres triggers (see
/// migration_14); the parent app just renders them. Keeping the
/// service separate from [KidDeviceService] so a future write
/// path doesn't accidentally bypass the trigger contract.
class KidDeviceEventService {
  final _supabase = Supabase.instance.client;

  /// Latest events for the current family, newest first. Limit
  /// defaults to 25 — the activity feed shows the recent slice
  /// only, anything older can wait for a future "view all" screen.
  Future<List<KidDeviceEvent>> listFamilyEvents({int limit = 25}) async {
    final rows = await _supabase
        .from('kid_device_events_with_context')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);

    return rows
        .map((r) => KidDeviceEvent.fromMap(r))
        .toList(growable: false);
  }
}

/// One row of kid_device_events_with_context. The view joins the
/// raw event with children + kid_devices for friendly display
/// labels. [devicePairingCode] is captured even after the code
/// row is deleted (cancel), so we can show "code 481302 cancelled"
/// in the feed.
class KidDeviceEvent {
  /// Same string identifiers as the migration_14 CHECK constraint.
  /// Exposed as constants so the UI can switch on them without
  /// string-typing magic strings in three different files.
  static const typeCodeGenerated = 'code_generated';
  static const typeCodeClaimed = 'code_claimed';
  static const typeCodeCancelled = 'code_cancelled';
  static const typeDeviceRevoked = 'device_revoked';

  final String id;
  final String eventType;
  final DateTime createdAt;
  final String? devicePairingCode;
  final String? childId;
  final String? childName;
  final String? kidDeviceId;
  final String? deviceName;

  const KidDeviceEvent({
    required this.id,
    required this.eventType,
    required this.createdAt,
    required this.devicePairingCode,
    required this.childId,
    required this.childName,
    required this.kidDeviceId,
    required this.deviceName,
  });

  factory KidDeviceEvent.fromMap(Map<String, dynamic> map) => KidDeviceEvent(
        id: map['id'] as String,
        eventType: map['event_type'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        devicePairingCode: map['device_pairing_code'] as String?,
        childId: map['child_id'] as String?,
        childName: map['child_name'] as String?,
        kidDeviceId: map['kid_device_id'] as String?,
        deviceName: map['device_name'] as String?,
      );

  /// Human-readable one-liner for the activity feed row. Kept here
  /// (not in the widget) so the wording is testable and easy to
  /// tweak in one place when we add event types later.
  String label() {
    final who = childName ?? 'a kid';
    final what = deviceName ?? 'a device';
    final code = devicePairingCode;
    switch (eventType) {
      case KidDeviceEvent.typeCodeGenerated:
        return code == null
            ? 'Generated a pairing code for $who'
            : 'Generated pairing code $code for $who';
      case KidDeviceEvent.typeCodeClaimed:
        return '$who paired $what';
      case KidDeviceEvent.typeCodeCancelled:
        return code == null
            ? 'Cancelled an unused pairing code'
            : 'Cancelled pairing code $code';
      case KidDeviceEvent.typeDeviceRevoked:
        return 'Revoked $what (was paired to $who)';
      default:
        return 'Unknown kid-device event';
    }
  }

  /// Humanizer for the timestamp. Mirrors the format used by
  /// KidDevice.lastSeenLabel so the feed feels consistent.
  String ageLabel(DateTime now) {
    final delta = now.difference(createdAt);
    if (delta.inSeconds < 30) return 'Just now';
    if (delta.inMinutes < 1) return '${delta.inSeconds}s ago';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}
