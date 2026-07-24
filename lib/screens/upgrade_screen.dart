import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/df_kit.dart';

class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key});

  static const int freeLimit = 3;

  static const List<String> _values = [
    'Unlimited sessions & up to 5 kids',
    'Priority AI & smarter checks',
    'Schedules, streaks & co-parents',
  ];

  void _startTrial(BuildContext context) {
    // Mock checkout — no payment wiring yet. Surfaces feedback so the
    // button doesn't feel dead while the real purchase flow is built.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checkout isn\'t wired up yet — coming soon.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.amberTint,
                borderRadius: BorderRadius.circular(AppRadius.tile),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                color: AppColors.amber,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'DoneFirst Plus',
            textAlign: TextAlign.center,
            style: AppText.title(size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            'Unlimited focus, the whole family.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 15),
          ),
          const SizedBox(height: 10),
          Text(
            'You\'ve used all $freeLimit free sessions this month.',
            textAlign: TextAlign.center,
            style: AppText.caption(color: AppColors.amberDeep),
          ),
          const SizedBox(height: 24),
          DfCard(
            child: Column(
              children: _values
                  .map(
                    (v) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: AppColors.greenTint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              LucideIcons.check,
                              size: 15,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              v,
                              style: AppText.body(size: 14, w: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PlanCard(name: 'Plus', price: '\$4.99', best: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PlanCard(name: 'Pro', price: '\$9.99', best: false),
              ),
            ],
          ),
          const SizedBox(height: 24),
          DfButton.amber(
            'Start 7-day free trial',
            icon: LucideIcons.sparkles,
            onPressed: () => _startTrial(context),
          ),
          const SizedBox(height: 10),
          Text(
            'Then \$4.99/mo · cancel anytime',
            textAlign: TextAlign.center,
            style: AppText.caption(),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String price;
  final bool best;
  const _PlanCard({
    required this.name,
    required this.price,
    required this.best,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DfCard(
          borderColor: best ? AppColors.green : AppColors.borderCol,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: AppText.cardHeader(size: 16)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: AppText.statValue(size: 26)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3, left: 3),
                    child: Text('/mo', style: AppText.caption()),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (best)
          Positioned(
            top: -10,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.green,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                'BEST VALUE',
                style: AppText.label(color: Colors.white, size: 10),
              ),
            ),
          ),
      ],
    );
  }
}
