import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';

class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  static const int freeLimit = 3;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade Plan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 16),
          _buildPlanCard(
            icon: LucideIcons.checkCircle2,
            name: 'Free',
            price: '\$0',
            period: '/mo',
            color: AppColors.textSecondary,
            features: [
              'Up to $freeLimit lock sessions/mo',
              '1 child',
              'Basic proof verification',
              'Email support',
            ],
            isSelected: false,
          ),
          const SizedBox(height: 16),
          _buildPlanCard(
            icon: LucideIcons.sparkles,
            name: 'DoneFirst Plus',
            price: '\$4.99',
            period: '/mo',
            color: AppColors.primary,
            features: [
              'Unlimited lock sessions',
              'Up to 4 children',
              'Priority AI verification',
              'Push notifications',
              'Session history & stats',
            ],
            isPopular: true,
            isSelected: true,
          ),
          const SizedBox(height: 16),
          _buildPlanCard(
            icon: LucideIcons.crown,
            name: 'DoneFirst Pro',
            price: '\$9.99',
            period: '/mo',
            color: AppColors.accent,
            features: [
              'Everything in Plus',
              'Up to 10 children',
              'Co-parent accounts (2 parents)',
              'Recurring homework schedules',
              'Monthly progress reports',
              'Email + chat support',
            ],
            isSelected: false,
          ),
          const SizedBox(height: 32),
          Text(
            'Your first lock session is free. No credit card required to start.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPlanCard({
    required IconData icon,
    required String name,
    required String price,
    required String period,
    required Color color,
    required List<String> features,
    bool isPopular = false,
    bool isSelected = false,
  }) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: color, width: 2) : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, color: color, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            price,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              period,
                              style: TextStyle(
                                fontSize: 14,
                                color: color.withValues(alpha:0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...features.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(LucideIcons.check, size: 18, color: color),
                          const SizedBox(width: 8),
                          Text(f, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (isPopular)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Popular',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
