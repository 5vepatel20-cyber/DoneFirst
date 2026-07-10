import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';
import 'services/auth_service.dart';
import 'services/realtime_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/parent_dashboard.dart';
import 'screens/session_complete_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/upgrade_screen.dart';

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
            case '/auth':
              return MaterialPageRoute(builder: (_) => const AuthScreen());
            case '/dashboard':
              return MaterialPageRoute(builder: (_) => const ParentDashboard());
            case '/settings':
              return MaterialPageRoute(builder: (_) => const SettingsScreen());
            case '/upgrade':
              return MaterialPageRoute(builder: (_) => const UpgradeScreen());
            case '/session-complete':
              // Caller pushes with arguments in the route settings
              // (childName, tasksCompleted, streakDays,
              // minutesStudied). For simplicity we instantiate with
              // placeholders; the canonical entry is from kid_home
              // after a session wraps.
              final args = settings.arguments as Map<String, dynamic>? ?? {};
              return MaterialPageRoute(
                builder: (_) => SessionCompleteScreen(
                  childName: args['childName'] as String? ?? '',
                  tasksCompleted: args['tasksCompleted'] as int? ?? 0,
                  streakDays: args['streakDays'] as int? ?? 0,
                  minutesStudied: args['minutesStudied'] as int?,
                  onDone: () => Navigator.of(_).pop(),
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

  Future<void> _resolveRoute() async {
    if (!mounted) return;
    if (_auth.currentUser != null) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      final prefs = await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool('onboarding_done') ?? false;
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          onboardingDone ? '/auth' : '/onboarding',
        );
      }
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
