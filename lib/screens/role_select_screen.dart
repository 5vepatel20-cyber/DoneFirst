import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/df_kit.dart';
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
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Center(child: BrandLogo.signIn()),
              const SizedBox(height: 24),
              Text(
                'Set up this device',
                style: AppText.label(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Who's going to use it?",
                style: AppText.screenTitle(),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _RoleCard(
                icon: LucideIcons.user,
                title: "I'm the parent",
                subtitle: 'Manage kids, approve work, set rules',
                onTap: () =>
                    Navigator.of(context).pushReplacementNamed('/auth'),
              ),
              const SizedBox(height: 14),
              _RoleCard(
                icon: LucideIcons.smartphone,
                title: "This is my kid's device",
                subtitle: 'Pair it with a parent, then hand it over',
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const KidRoot()),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Most families install on the parent\'s phone first, '
                  'then set up each kid\'s device.',
                  style: AppText.caption(),
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
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DfCard(
      onTap: onTap,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.greenTint,
              borderRadius: BorderRadius.circular(AppRadius.iconTile),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: AppColors.green, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.cardHeader(size: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: AppText.bodySecondary(size: 13)),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            color: AppColors.ink45,
            size: 20,
          ),
        ],
      ),
    );
  }
}
