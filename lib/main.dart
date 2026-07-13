import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';
import 'services/auth_service.dart';
import 'services/profile_service.dart';
import 'services/realtime_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/role_select_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/parent_dashboard.dart';
import 'screens/session_complete_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/upgrade_screen.dart';
import 'screens/kid/kid_root.dart';

final realtimeService = RealtimeService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();

  // Sentry crash reporting. To enable, build with:
  //   flutter build apk --dart-define=SENTRY_DSN=https://...@sentry.io/...
  // If SENTRY_DSN is not set, String.fromEnvironment returns ''
  // and SentryFlutter.init becomes a no-op (no network calls,
  // no overhead). See LAUNCH_CHECKLIST.md section 7.1.
  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.tracesSampleRate = 0.1;
      options.environment = const String.fromEnvironment(
        'SENTRY_ENV',
        defaultValue: 'production',
      );
      // Single-app mode (parent + kid in one APK) — single release
      // stream. Old kid-app tag is gone since both modes ship as
      // one binary.
      options.release = const String.fromEnvironment(
        'SENTRY_RELEASE',
        defaultValue: 'dev',
      );
      options.dist = const String.fromEnvironment(
        'SENTRY_DIST',
        defaultValue: 'dev',
      );
      options.beforeSend = (event, hint) {
        final msg = event.message?.toString() ?? '';
        // Drop exceptions whose message looks like a Supabase JWT.
        if (msg.contains('eyJ') && msg.contains('.')) {
          return null;
        }
        return event;
      };
    },
    appRunner: () => runApp(const DoneFirstApp()),
  );
}

class DoneFirstApp extends StatelessWidget {
  const DoneFirstApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (ctx, isDark, _) => MaterialApp(
        title: 'DoneFirst',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/':
              return MaterialPageRoute(builder: (_) => const EntryPoint());
            case '/onboarding':
              return MaterialPageRoute(
                builder: (_) => const OnboardingScreen(),
              );
            case '/role-select':
              return MaterialPageRoute(
                builder: (_) => const RoleSelectScreen(),
              );
            case '/auth':
              return MaterialPageRoute(builder: (_) => const AuthScreen());
            case '/kid':
              return MaterialPageRoute(
                builder: (_) => const KidRoot(),
              );
            case '/dashboard':
              return MaterialPageRoute(
                builder: (_) => const ParentDashboard(),
              );
            case '/settings':
              return MaterialPageRoute(builder: (_) => const SettingsScreen());
            case '/upgrade':
              return MaterialPageRoute(builder: (_) => const UpgradeScreen());
            case '/session-complete':
              final args = settings.arguments as Map<String, dynamic>? ?? {};
              return MaterialPageRoute(
                builder: (_) => SessionCompleteScreen(
                  childName: args['childName'] as String? ?? '',
                  tasksCompleted: args['tasksCompleted'] as int? ?? 0,
                  streakDays: args['streakDays'] as int? ?? 0,
                  minutesStudied: args['minutesStudied'] as int?,
                  onDone: () => Navigator.of(context).pop(),
                ),
              );
            default:
              return MaterialPageRoute(builder: (_) => const EntryPoint());
          }
        },
      ),
    );
  }
}

class EntryPoint extends StatefulWidget {
  const EntryPoint({super.key});

  @override
  State<EntryPoint> createState() => _EntryPointState();
}

class _EntryPointState extends State<EntryPoint> {
  final _auth = AuthService();
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    // Light status bar on the splash — once we route away the new
    // screen will set its own style via AnnotatedRegion.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    // Hold the splash for at least 600ms so the logo animation
    // doesn't flicker on fast devices. Auth check happens in parallel.
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 600)),
      _resolveRoute(),
    ]);
    if (mounted) setState(() => _checking = false);
  }

  /// Routes the user based on auth + role. Kids never go through
  /// the parent signup screen — if the auth client has no user we
  /// land on RoleSelectScreen, which itself branches to AuthScreen
  /// (parent) or KidRoot (kid). If we do have a user, fetch the
  /// role from the parents table and route by it.
  Future<void> _resolveRoute() async {
    if (!mounted) return;
    if (_auth.currentUser == null) {
      final prefs = await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool('onboarding_done') ?? false;
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          onboardingDone ? '/role-select' : '/onboarding',
        );
      }
      return;
    }

    // Authenticated. Read role from the parents row.
    final profileService = ProfileService();
    String? role;
    try {
      final profile = await profileService.getParentProfile();
      role = profile?.role;
    } catch (_) {
      // If the parents row is missing or unreadable we treat as
      // unsigned and bounce back to the role chooser. This can
      // happen if the kid-app signup raced and the row hasn't
      // landed yet.
      role = null;
    }

    if (!mounted) return;
    if (role == 'kid') {
      Navigator.pushReplacementNamed(context, '/kid');
    } else {
      Navigator.pushReplacementNamed(context, '/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The Splash is the entry-point visual; routing happens once
    // the auth check resolves and pushes a replacement route.
    if (_checking) return const SplashScreen();
    return const SizedBox.shrink();
  }
}
