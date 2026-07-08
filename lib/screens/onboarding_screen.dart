import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _pages = [
    _OnboardingPage(
      icon: Icons.shield_outlined,
      title: 'Block Distractions',
      description:
          'Lock distracting apps on your child\'s device until homework is done. They focus, you relax.',
      color: AppColors.primary,
    ),
    _OnboardingPage(
      icon: Icons.camera_alt_outlined,
      title: 'Photo Proof Required',
      description:
          'Kids submit a photo of their completed work. Mistral AI verifies it\'s real homework — no shortcuts.',
      color: AppColors.accent,
    ),
    _OnboardingPage(
      icon: Icons.check_circle_outline,
      title: 'You Stay In Control',
      description:
          'Approve or reject proof submissions. Set study sessions, break times, and auto-unlock rules.',
      color: AppColors.success,
    ),
    _OnboardingPage(
      icon: Icons.rocket_launch_outlined,
      title: 'Ready to Start?',
      description:
          'Create your family account and add your first child in under 2 minutes.',
      color: AppColors.primary,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: () => _done(context),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: _pages.length,
                itemBuilder: (ctx, i) => _buildPage(_pages[i]),
              ),
            ),
            _buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: page.color.withValues(alpha:0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(page.icon, size: 80, color: page.color),
          ),
          const SizedBox(height: 48),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == i
                      ? AppColors.primary
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (_currentPage == _pages.length - 1) {
                  _done(context);
                } else {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: Text(
                _currentPage == _pages.length - 1 ? 'Get Started' : 'Next',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _done(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/auth');
    }
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
