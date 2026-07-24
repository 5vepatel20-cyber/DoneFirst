import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _pages = const [
    _OnboardingPage(
      icon: LucideIcons.bookOpen,
      title: 'Homework first',
      description:
          "Set a focus session — the distracting apps pause until the "
          "work's done.",
    ),
    _OnboardingPage(
      icon: LucideIcons.shieldCheck,
      title: 'Distractions pause',
      description:
          'Social, games and video wait quietly — nothing deleted, '
          'nothing lost.',
    ),
    _OnboardingPage(
      icon: LucideIcons.camera,
      title: 'Snap the finished work',
      description:
          'A quick photo. Our AI gives it a first look and flags only '
          'what needs your eyes.',
    ),
    _OnboardingPage(
      icon: LucideIcons.sparkles,
      title: 'Earn the rest',
      description:
          "Work approved → apps unlock instantly. Streaks build. "
          "Everyone stays calm.",
    ),
  ];

  bool get _isLastPage => _currentPage == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.topRight,
                child: _isLastPage
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(
                          right: AppSpacing.screenPadding,
                        ),
                        child: TextButton(
                          onPressed: () => _done(context),
                          child: Text(
                            'Skip',
                            style: AppText.button(
                              color: AppColors.ink45,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            alignment: Alignment.center,
            child: Icon(page.icon, size: 56, color: AppColors.green),
          ),
          const SizedBox(height: 40),
          Text(
            page.title,
            style: AppText.screenTitle(size: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            page.description,
            style: AppText.body(size: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
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
                      ? AppColors.green
                      : AppColors.borderCol,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (_isLastPage)
            DfButton('Get started', onPressed: () => _done(context))
          else
            Row(
              children: [
                const Spacer(),
                _NextArrow(
                  onTap: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _done(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (context.mounted) {
      // Onboarding is role-neutral, so it hands off to the
      // "Who's using this device?" chooser rather than dumping
      // everyone into the parent signup form.
      Navigator.of(context).pushReplacementNamed('/role-select');
    }
  }
}

class _NextArrow extends StatelessWidget {
  const _NextArrow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.green,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: AppColors.greenDeep, offset: const Offset(0, 4)),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(
          LucideIcons.arrowRight,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
  });
}
