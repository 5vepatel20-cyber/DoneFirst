import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_config.dart';

/// Owns the kid-app identity lifecycle:
///   - claimPairingCode(code) → POST to claim-pairing Edge Function,
///     store returned access_token + refresh_token, call
///     Supabase.auth.recoverSession to materialize a Supabase session.
///   - persistSession() → write tokens to SharedPreferences.
///   - restoreSession() → on app launch, rebuild the Supabase
///     session from persisted tokens.
///   - signOut() → clear tokens and Supabase session, kid sees the
///     pairing screen again.
///
/// Token storage rationale: SharedPreferences is encrypted at rest
/// by Android (each app's prefs live under its own UID; the OS
/// encrypts the file with the device-bound key). It's not as
/// tamper-proof as Keystore but it matches what the parent app does
/// and the threat model (kid with USB debugging can already break
/// the kiosk with `adb shell dpm remove-active-admin`) doesn't
/// justify the extra plumbing.
class KidAuthService extends ChangeNotifier {
  static const _kAccessToken = 'kid_access_token';
  static const _kRefreshToken = 'kid_refresh_token';
  // Stored in the same encrypted-at-rest SharedPreferences blob as
  // the tokens. Non-secret — it's just the kid's first name for
  // the lock-screen greeting — but kept off the JWT to avoid
  // stampeding the payload every time the parent renames the kid.
  static const _kChildName = 'kid_display_name';

  final SupabaseClient _supabase;
  final http.Client _http;

  /// Production constructor. Uses the default SupabaseClient and a
  /// real http.Client.
  KidAuthService({http.Client? httpClient})
    : _supabase = Supabase.instance.client,
      _http = httpClient ?? http.Client();

  /// Test-only constructor taking both an http.Client and the
  /// SupabaseClient. Production should not use this — leave
  /// [supabaseClient] null to use the default instance.
  @visibleForTesting
  KidAuthService.withDeps({
    required http.Client httpClient,
    SupabaseClient? supabaseClient,
  }) : _supabase = supabaseClient ?? Supabase.instance.client,
       _http = httpClient;

  /// Child id carried in the JWT's app_metadata. Used to scope
  /// realtime subscriptions and break-request inserts.
  String? _childId;
  String? _familyId;
  String? _deviceId;
  /// Kid's display name, captured during claim-pairing from the
  /// edge function's child_name field. Persisted to
  /// SharedPreferences so it survives a cold launch where the
  /// JWT is restored but we no longer hit the edge function.
  String? _childName;

  String? get childId => _childId;
  String? get familyId => _familyId;
  String? get deviceId => _deviceId;
  /// Returns the kid's display name if known, else null. Callers
  /// should fall back to a generic greeting ("there") when null.
  String? get childName => _childName;
  bool get isPaired => _supabase.auth.currentSession != null;

  /// Exchange a 6-digit pairing code for a Supabase session.
  ///
  /// Throws a [KidAuthException] on any failure so the pairing
  /// screen can show a clean snackbar instead of a raw HTTP error.
  Future<void> claimPairingCode(String code, {String? deviceName}) async {
    final url = Uri.parse('$supabaseUrl/functions/v1/claim-pairing');
    final response = await _http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            // No Authorization header — this is the unauthenticated
            // bootstrap call. The edge function validates the code
            // and mints the JWT.
            'apikey': supabaseAnonKey,
          },
          body: jsonEncode({
            'code': code,
            // Trim and treat whitespace-only as empty so a parent
            // who tapped space twice doesn't end up with a device
            // whose name on the dashboard reads "  ".
            if (deviceName != null && deviceName.trim().isNotEmpty)
              'device_name': deviceName.trim(),
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 410) {
      throw const KidAuthException('Invalid or expired code', code: 'EXPIRED');
    }
    if (response.statusCode == 400) {
      final body = _safeJson(response.body);
      throw KidAuthException(
        body['error']?.toString() ?? 'Code must be 6 digits',
        code: 'BAD_CODE',
      );
    }
    if (response.statusCode != 200) {
      throw KidAuthException(
        'Could not pair right now. Try again in a moment.',
        code: 'SERVER_ERROR',
      );
    }
    final body = _safeJson(response.body);
    if (body['success'] != true) {
      throw KidAuthException(
        body['error']?.toString() ?? 'Pairing failed',
        code: 'SERVER_ERROR',
      );
    }
    final access = body['access_token']?.toString();
    final refresh = body['refresh_token']?.toString();
    if (access == null || refresh == null) {
      throw const KidAuthException(
        'Server returned no session',
        code: 'BAD_RESPONSE',
      );
    }

    // Materialize a Supabase session locally so RealtimeChannel
    // picks up the auth state for downstream filters.
    try {
      await _supabase.auth.recoverSession(access);
    } catch (e) {
      // recoverSession can throw on a malformed token (it's a JSON
      // decode under the hood) or on a refresh rotation that the
      // server rejected. We don't want that to abort the pairing
      // — the parent app's device list still got its kid_devices
      // row written by the edge function, so the kid is paired on
      // the server side. We persist the tokens and let the user
      // see the locked/unlocked screen; the next realtime
      // round-trip will fail-and-retry if the JWT is truly bad.
      debugPrint('recoverSession after claim-pairing failed: $e');
    }
    // We persist both tokens so we can rebuild after a cold launch
    // (see restoreSession below) regardless of whether the local
    // recoverSession succeeded.
    await _persistTokens(access, refresh);

    _childId = body['child_id']?.toString();
    _familyId = body['family_id']?.toString();
    _deviceId = body['device_id']?.toString();
    // The edge function looks up the kid's name on the server side
    // (RLS keeps the kid from reading children directly). Persist
    // it alongside the tokens so a cold launch can greet the kid
    // by name without an extra round-trip.
    final claimedName = body['child_name']?.toString().trim();
    await _persistChildName(claimedName == null || claimedName.isEmpty
        ? null
        : claimedName);
    _childName = claimedName == null || claimedName.isEmpty
        ? null
        : claimedName;
    notifyListeners();
  }

  /// Re-hydrate the Supabase session from previously-persisted
  /// tokens. Called once on app launch from main() before deciding
  /// whether to show the pairing screen or the unlocked screen.
  ///
  /// Returns true if a valid session was restored.
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final access = prefs.getString(_kAccessToken);
      final refresh = prefs.getString(_kRefreshToken);
      if (access == null || refresh == null) return false;
      await _supabase.auth.recoverSession(access);
      // Pull child_id / family_id from the JWT's app_metadata claim.
      // Auth.currentUser is non-null after recoverSession.
      final user = _supabase.auth.currentUser;
      if (user == null) {
        await _clearTokens();
        return false;
      }
      final meta = user.appMetadata;
      _childId = meta['child_id']?.toString();
      _familyId = meta['family_id']?.toString();
      _deviceId = meta['device_id']?.toString();
      if (_childId == null || _familyId == null || _deviceId == null) {
        // The token doesn't look like one we minted — fail safe by
        // clearing it so the kid lands back on the pairing screen.
        await _clearTokens();
        return false;
      }
      // Pull the cached child_name so the lock screen can greet
      // the kid after a cold launch. Stored at pair time, not from
      // the JWT (which only carries ids).
      final cachedName = prefs.getString(_kChildName)?.trim();
      _childName = (cachedName != null && cachedName.isNotEmpty)
          ? cachedName
          : null;
      notifyListeners();
      return true;
    } catch (e) {
      // recoverSession throws on expired/invalid tokens. Clear
      // them so a stale token can't trap the kid on a black screen
      // and they get a fresh pairing prompt.
      debugPrint('restoreSession error: $e');
      await _clearTokens();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // The local session is gone from memory regardless of
      // remote-side failure — keep going with token cleanup.
    }
    await _clearTokens();
    _childId = null;
    _familyId = null;
    _deviceId = null;
    _childName = null;
    notifyListeners();
  }

  Future<void> _persistTokens(String access, String refresh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccessToken, access);
    await prefs.setString(_kRefreshToken, refresh);
  }

  Future<void> _persistChildName(String? name) async {
    // SharedPreferences doesn't expose a "setOrRemove" — pass null
    // when the name is missing so a stale value from a previous
    // pairing doesn't haunt a fresh pairing of a different kid on
    // the same physical device.
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_kChildName);
    } else {
      await prefs.setString(_kChildName, name);
    }
  }

  Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccessToken);
    await prefs.remove(_kRefreshToken);
  }

  Map<String, dynamic> _safeJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }
}

/// Distinct exception type so the UI can show actionable copy
/// instead of a generic "Something went wrong" toast.
class KidAuthException implements Exception {
  final String message;
  final String code;
  const KidAuthException(this.message, {required this.code});

  @override
  String toString() => 'KidAuthException($code): $message';
}
