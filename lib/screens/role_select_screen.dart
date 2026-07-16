import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import 'kid/kid_root.dart';

/// First-launch screen for unauthenticated users. Asks "are you a
/// parent or a kid?" and routes accordingly. The choice is purely a
/// routing decision; nothing is persisted — if a parent accidentally
/// taps "I'm a kid" they just see PairingScreen and can back out to
/// here.
///
/// Why a dedicated screen rather than a toggle on AuthScreen:
///   • Kids have a fundamentally different flow (6-digit code, no
///     password) — putting it behind a parent signup form would be
///     confusing.
///   • Parents need to see consent disclosures before they type.
///   • A fullscreen chooser is also a chance to brand the first
///     impression; the parent signup flow is dense and busy.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Center(
                child: BrandLogo(
                  size: 56,
                  tileColor: AppColors.forest,
                  glyphColor: AppColors.kidBg,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Who’s using this device?',
                style: AppText.screenTitle(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'DoneFirst is one app. Pick how you’ll use it on '
                'this phone.',
                style: AppText.bodySecondary(size: 14),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _RoleCard(
                icon: LucideIcons.user,
                title: 'I’m a parent',
                subtitle: 'Set homework timers, see proofs, manage '
                    'devices.',
                color: AppColors.forest,
                onTap: () => Navigator.of(context).pushReplacementNamed(
                  '/auth',
                ),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: LucideIcons.smartphone,
                title: 'I’m a kid',
                subtitle: 'Type the 6-digit code your parent set up.',
                color: AppColors.grass,
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const KidRoot(),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'You can sign out and switch any time.',
                  style: AppText.bodySecondary(size: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.cardHeader(size: 16)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppText.bodySecondary(size: 13),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: AppColors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}