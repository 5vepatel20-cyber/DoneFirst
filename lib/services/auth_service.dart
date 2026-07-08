import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

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
