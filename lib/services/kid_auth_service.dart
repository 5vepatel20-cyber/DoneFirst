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
///     Supabase.auth.setSession to materialize a Supabase session.
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
  /// True when we have either a live Supabase session or a decoded
  /// kid identity from persisted tokens.  The two paths cover:
  ///   1. setSession succeeded → currentSession is set (normal path)
  ///   2. setSession failed (web CORS) but JWT decode succeeded →
  ///      _childId is set (offline fallback)
  /// PairingScreen has its own KidAuthService instance that shares
  /// the same Supabase client, so path 1 triggers the screen
  /// transition via the shared currentSession.
  bool get isPaired => _supabase.auth.currentSession != null || _childId != null;

  /// Return the current access token, preferring the live Supabase
  /// session and falling back to the persisted token in
  /// SharedPreferences.  Used by HeartbeatService (and any other
  /// caller that needs a raw Bearer token) so they don't break
  /// when setSession failed on web and _supabase.auth.currentSession
  /// is null.
  Future<String?> getAccessToken() async {
    // Fast path: live session exists.
    final live = _supabase.auth.currentSession?.accessToken;
    if (live != null) return live;
    // Slow path: read from localStorage / SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAccessToken);
  }

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

    await _persistTokens(access, refresh);

    // Materialize a Supabase session so currentSession is non-null
    // and RealtimeChannel picks up the auth state for downstream
    // filters.  setSession takes the refresh token + optional access
    // token; it decodes the JWT locally and calls GET /auth/v1/user
    // to hydrate the user object. recoverSession() was broken — it
    // expects a full Session JSON string, not a raw access token.
    // Timeout: on web the /auth/v1/user call may be slow or fail.
    try {
      await _supabase.auth
          .setSession(refresh, accessToken: access)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('setSession after claim-pairing failed: $e');
    }

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

      // Try setSession with a generous timeout. On web this calls
      // GET /auth/v1/user which may be slow due to CORS preflight.
      // A failed setSession is not fatal — getAccessToken() and
      // isPaired both fall back to the persisted tokens / JWT decode.
      try {
        await _supabase.auth
            .setSession(refresh, accessToken: access)
            .timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('setSession in restoreSession failed: $e');
        // Retry once without timeout — the SDK's internal retry may
        // succeed on a slow network where the first attempt timed out.
        try {
          await _supabase.auth
              .setSession(refresh, accessToken: access)
              .timeout(const Duration(seconds: 20));
        } catch (e2) {
          debugPrint('setSession retry in restoreSession failed: $e2');
        }
      }

      // If setSession succeeded, currentUser is populated.
      // Otherwise fall back to decoding the JWT payload directly.
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final meta = user.appMetadata;
        _childId = meta['child_id']?.toString();
        _familyId = meta['family_id']?.toString();
        _deviceId = meta['device_id']?.toString();
      }
      if (_childId == null) {
        // setSession failed or user has no kid claims. Decode the
        // access token JWT payload (base64url JSON, not encrypted)
        // to extract app_metadata without a network call.
        final claims = _decodeJwtPayload(access);
        if (claims != null) {
          final meta = claims['app_metadata'] as Map<String, dynamic>?;
          _childId = meta?['child_id']?.toString();
          _familyId = meta?['family_id']?.toString();
          _deviceId = meta?['device_id']?.toString();
        }
      }
      if (_childId == null || _familyId == null || _deviceId == null) {
        await _clearTokens();
        return false;
      }
      final cachedName = prefs.getString(_kChildName)?.trim();
      _childName = (cachedName != null && cachedName.isNotEmpty)
          ? cachedName
          : null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('restoreSession error: $e');
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

  /// Decode the payload portion of a JWT without verification.
  /// Used as a fallback when setSession / recoverSession fail on
  /// web (CORS, network timeout) so we can still extract
  /// app_metadata claims (child_id, family_id, device_id).
  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      // base64url → base64 padding
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      return jsonDecode(
        utf8.decode(base64Decode(payload)),
      ) as Map<String, dynamic>;
    } catch (_) {
      return null;
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
