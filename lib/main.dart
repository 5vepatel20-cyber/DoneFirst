import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'supabase_config.dart';
import 'services/auth_service.dart';
import 'services/realtime_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/parent_dashboard.dart';
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
    await Future.delayed(const Duration(milliseconds: 500));
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
    setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha:0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'DoneFirst',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Homework first. Apps after.',
                style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
