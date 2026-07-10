import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  // OAuth client IDs are injected at build time via --dart-define.
  // Empty when running without those defines; we surface a clear
  // error in that case instead of letting google_sign_in throw a
  // cryptic clientConfigurationError.
  static const String _webClientId =
      String.fromEnvironment('G_OAUTH_WEB_CLIENT_ID');
  static const String _iosClientId =
      String.fromEnvironment('G_OAUTH_IOS_CLIENT_ID');

  Future<void> resendVerification() async {
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: _supabase.auth.currentUser!.email!,
    );
  }

  Future<User?> signUp(
    String email,
    String password,
    String displayName,
  ) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    );
    return response.user;
  }

  Future<User?> signIn(String email, String password) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user;
  }

  /// Sign in (or sign up — Supabase auto-creates on first Google use)
  /// via Google. Branches on platform:
  ///   - Web: Supabase's built-in OAuth redirect flow.
  ///   - Android/iOS: native google_sign_in → signInWithIdToken.
  ///
  /// On web, returns the current session if the redirect already
  /// completed (caller should listen to onAuthStateChange). On
  /// native, returns the freshly-signed-in user.
  ///
  /// Throws on:
  ///   - User cancelled the Google account picker.
  ///   - OAuth client IDs weren't configured (G_OAUTH_WEB_CLIENT_ID).
  ///   - Platform plugin failure.
  Future<User?> signInWithGoogle() async {
    if (kIsWeb) {
      // Supabase handles the full OAuth round-trip via redirect.
      // The session lands via onAuthStateChange when the browser
      // returns; currentSession is non-null only if a previous
      // sign-in already completed in this tab.
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        // Web uses Supabase's Site URL; passing redirectTo here
        // can be silently overwritten (Supabase discussion #33014)
        // so we leave it null and rely on the dashboard config.
      );
      return _supabase.auth.currentUser;
    }

    // Native (Android + iOS): need the web OAuth client ID. serverClientId
    // is mandatory for google_sign_in_android 7.x.
    if (_webClientId.isEmpty) {
      throw const GoogleSignInConfigException(
        'Google Sign In is not configured. Rebuild with '
        '--dart-define=G_OAUTH_WEB_CLIENT_ID=... and '
        '--dart-define=G_OAUTH_IOS_CLIENT_ID=...',
      );
    }

    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      clientId: _iosClientId.isEmpty ? null : _iosClientId,
      serverClientId: _webClientId,
    );

    final GoogleSignInAccount account;
    try {
      account = await googleSignIn.authenticate(scopeHint: const ['email']);
    } on Exception catch (e) {
      // google_sign_in throws on user cancel too — wrap any caught
      // exception as a "cancelled" rather than a hard failure, then
      // rethrow if it looks like a real plugin error.
      final msg = e.toString().toLowerCase();
      if (msg.contains('cancel') || msg.contains('aborted')) {
        throw const GoogleSignInCancelledException();
      }
      rethrow;
    }

    // idToken and accessToken live on different objects in 7.x:
    //   - account.authentication → GoogleSignInAuthentication (idToken)
    //   - authorizationClient.authorizationForScopes → accessToken
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const GoogleSignInConfigException(
        'Google returned no ID token. Check OAuth consent screen config.',
      );
    }

    final authorization = await googleSignIn.authorizationClient
        .authorizationForScopes(const ['email']);
    final accessToken = authorization?.accessToken;

    final response = await _supabase.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
      // nonce intentionally omitted — google_sign_in 7.x has no public
      // nonce API. Supabase dashboard has "Skip nonce check" enabled
      // to allow this.
    );
    return response.user;
  }

  /// Best-effort display name for a freshly-signed-in user. Google
  /// auth providers return this in the user metadata `name` field.
  /// Falls back to the email local-part so we always have something
  /// non-empty to seed the `parents` row with.
  static String deriveDisplayName(User user) {
    final metaName = user.userMetadata?['full_name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) {
      return metaName.trim();
    }
    final metaNameAlt = user.userMetadata?['name'] as String?;
    if (metaNameAlt != null && metaNameAlt.trim().isNotEmpty) {
      return metaNameAlt.trim();
    }
    final email = user.email ?? '';
    final atIndex = email.indexOf('@');
    if (atIndex <= 0) return email.isEmpty ? 'Parent' : email;
    return email.substring(0, atIndex);
  }

  /// True when [user] was created within the last 60 seconds. Used
  /// by the UI to decide whether to route a Google sign-in to the
  /// consent capture screen (first time) or straight to the dashboard
  /// (returning user). 60s is generous enough to cover any lag in the
  /// OAuth round-trip without falsely flagging returning users whose
  /// account is genuinely recent.
  static bool isFreshGoogleSignIn(User user) {
    final createdAt = user.createdAt;
    // Supabase returns createdAt as an ISO-8601 string (always
    // present for non-anonymous users). Guard against the
    // just-in-case null and against an unparseable format.
    if (createdAt.isEmpty) return false;
    final created = DateTime.tryParse(createdAt);
    if (created == null) return false;
    final age = DateTime.now().difference(created);
    return age.inSeconds.abs() < 60;
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  Future<void> changePassword(String newPassword) async {
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> deleteAccount() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final token = _supabase.auth.currentSession?.accessToken ?? '';

    await http.post(
      Uri.parse('https://wxjtksxugsirpowptpmz.supabase.co/functions/v1/delete-account'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    await _supabase.auth.signOut();
  }
}

/// Thrown when Google Sign In is called without the OAuth client IDs
/// being configured at build time. Distinct from a normal error so
/// the UI can show actionable setup instructions instead of a generic
/// "something went wrong".
class GoogleSignInConfigException implements Exception {
  final String message;
  const GoogleSignInConfigException(this.message);
  @override
  String toString() => 'GoogleSignInConfigException: $message';
}

/// Thrown when the user dismissed the Google account picker without
/// picking one. UI should treat this as a soft cancel, not a failure.
class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
  @override
  String toString() => 'GoogleSignInCancelledException';
}
