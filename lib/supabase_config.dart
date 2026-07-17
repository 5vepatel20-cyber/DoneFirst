import 'package:supabase_flutter/supabase_flutter.dart';

/// Public Supabase project URL. Read from --dart-define at build
/// time so the secret stays out of source control. Use the same
/// value the parent app's previous build wired into initSupabase:
/// the project ref from the dashboard URL.
///
/// Build command:
///   flutter build apk --dart-define=SUPABASE_URL=https://&lt;ref&gt;.supabase.co
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://wxjtksxugsirpowptpmz.supabase.co',
);

/// Anon (publishable) key. Safe to embed in shipped code, but still
/// best practice to keep it out of git. Pass via --dart-define:
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// Direct-HTTP callers (HeartbeatService, KidAuthService for the
/// pairing bootstrap) need this so they can sign edge-function
/// requests without going through the Supabase client.
const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  // Safe to commit — anon keys are public by design. RLS is what
  // protects user data, not key secrecy. Override with
  // --dart-define=SUPABASE_ANON_KEY=... for non-public builds.
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind4anRrc3h1Z3NpcnBvd3B0cG16Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzMzMzMTgsImV4cCI6MjA5ODkwOTMxOH0.Ng9onu4901Q1yY0YnrM1XLyo5yOBoQbUariFqG-M3go',
);

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    // PKCE is required for OAuth on web (Supabase docs) and harmless
    // for the native password flow. Without it, signInWithOAuth on
    // web starts but never completes the round-trip.
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}
