import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import 'upgrade_screen.dart';

/// In-app help + FAQ. Lives in Settings so it's reachable from one
/// tap when a parent is stuck, instead of having to email support.
///
/// Categories are the ones parents actually ask about, in priority
/// order — installation questions at the top because that's what
/// new users hit first, billing/legal at the bottom because that's
/// what existing users ask.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const List<_FaqCategory> _categories = [
    _FaqCategory(
      title: 'Getting started',
      icon: LucideIcons.rocket,
      tint: AppColors.primary,
      items: [
        _FaqItem(
          question: 'How do I set up my kid\'s device?',
          answer:
              'Install DoneFirst on the device your kid uses. From the '
              'parent app, open Settings → Kid devices and tap your '
              "child's name to generate a 6-digit pairing code. On the "
              "kid's device, open DoneFirst, choose \"Kid\" at sign-up, "
              'and enter the code. The code expires in 10 minutes, so '
              'have both devices ready before generating it. The kid '
              "device then needs to be set as the device owner (one-time "
              'ADB command — see the in-app setup guide) so the lock can '
              'actually take over the home screen.',
        ),
        _FaqItem(
          question: 'Why does the kid-side app need so many permissions?',
          answer:
              'The AccessibilityService (Android) or FamilyControls (iOS) '
              'is what lets DoneFirst actually block other apps during '
              "your kid's homework time. Without it, the timer would "
              'run but the apps would still be open. We never read the '
              'content of those apps — only enforce that they close.',
        ),
        _FaqItem(
          question: 'How do I add a second child?',
          answer:
              "From the parent dashboard, tap 'Add Another Child' at "
              'the bottom of the screen, or long-press the child avatar '
              'to rename or delete.',
        ),
      ],
    ),
    _FaqCategory(
      title: 'Proofs & AI verification',
      icon: LucideIcons.badgeCheck,
      tint: AppColors.success,
      items: [
        _FaqItem(
          question: 'How does the AI verify a homework photo?',
          answer:
              'When your kid submits a photo, Mistral AI looks at it and '
              'returns a decision: approved, rejected, or needs_review. '
              'You always see the AI result plus the kid\'s note before '
              'deciding yourself — the AI is a first pass, not a '
              'replacement for your judgment.',
        ),
        _FaqItem(
          question: 'Why is "needs_review" showing up so often?',
          answer:
              'Mistral defaults to needs_review when it\'s not sure. '
              'If you\'re seeing it on every photo, the photos might '
              'be blurry or the AI is hitting its daily quota. The '
              'parent dashboard shows how many AI checks you\'ve '
              'used today; the free tier is 50.',
        ),
        _FaqItem(
          question: 'Can I bulk-approve proofs?',
          answer:
              "Yes — tap 'Review proofs' on the dashboard (or the "
              "'X proofs to review' chip on a child card), long-press "
              'one proof to enter selection mode, then tap the others '
              'you want to include and hit Approve / Reject at the '
              'bottom.',
        ),
      ],
    ),
    _FaqCategory(
      title: 'Notifications',
      icon: LucideIcons.bell,
      tint: AppColors.accent,
      items: [
        _FaqItem(
          question: "I'm not getting notifications.",
          answer:
              'Check three things: (1) Settings → Notifications in '
              'DoneFirst — make sure the type you want is toggled on. '
              "(2) Your phone's notification settings — make sure "
              'DoneFirst is allowed to send notifications. '
              '(3) Battery optimisation on Android — add DoneFirst to '
              'the unoptimised apps list or notifications can be '
              'silently dropped.',
        ),
        _FaqItem(
          question: 'How do I turn off only certain notifications?',
          answer:
              "Settings → Notifications. Each type (new proof, break "
              "request, session complete) has its own toggle. Changes "
              "apply instantly — no need to restart the app.",
        ),
      ],
    ),
    _FaqCategory(
      title: 'Account & privacy',
      icon: LucideIcons.shield,
      tint: AppColors.info,
      items: [
        _FaqItem(
          question: 'Where is my data stored?',
          answer:
              'All data lives in our Supabase database, hosted in the '
              "US region. Photos are stored in a private bucket — only "
              "your family can access them. We don't sell or share any "
              "data with third parties. Full details in Settings → "
              "Privacy Policy.",
        ),
        _FaqItem(
          question: 'How do I export or delete my data?',
          answer:
              'Settings → Your Data has a Download button that exports '
              'every record as a JSON file. To permanently delete, use '
              'Settings → Delete Account — this wipes all children, '
              'sessions, proofs, and consent records. Deletion is '
              'irreversible.',
        ),
        _FaqItem(
          question: 'What does the consent card at signup do?',
          answer:
              "It's our COPPA / GDPR-K audit trail — five separate "
              "acknowledgments (you're 18+, you're the guardian, you "
              "consent to data collection, you consent to AI "
              "verification, optional analytics opt-in) plus a typed "
              "signature. Each acceptance is recorded with a timestamp "
              "so we can prove you consented if a regulator asks.",
        ),
      ],
    ),
    _FaqCategory(
      title: 'Billing & plans',
      icon: LucideIcons.award,
      tint: AppColors.warning,
      items: [
        _FaqItem(
          question: 'How many free sessions do I get per month?',
          answer:
              '${UpgradeScreen.freeLimit} sessions per parent account, per '
              'calendar month. The counter is on the parent dashboard so '
              "you always know how many you have left. Sessions that "
              "didn't reach the minimum lock duration don't count.",
        ),
        _FaqItem(
          question: 'What does Upgrade unlock?',
          answer:
              "Unlimited sessions, lower-latency AI verification "
              "(priority Mistral quota), and co-parent accounts so two "
              "parents can share one family.",
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Help & Support', style: AppText.screenTitle())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Greeting + contact line so the parent doesn't have to
          // hunt for support email when stuck.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.headset,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need more help?',
                        style: AppText.cardHeader(),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Email support@donefirst.app and a human will '
                        'reply within one business day.',
                        style: AppText.bodySecondary(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._categories.map((c) => _CategorySection(category: c)),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  final _FaqCategory category;
  const _CategorySection({required this.category});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category.icon, size: 18, color: category.tint),
              const SizedBox(width: 6),
              Text(
                category.title,
                style: AppText.cardHeader(color: category.tint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: List.generate(category.items.length, (i) {
                final item = category.items[i];
                return Column(
                  children: [
                    _FaqTile(item: item),
                    if (i < category.items.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final _FaqItem item;
  const _FaqTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Removes the default ExpansionTile divider so the surrounding
      // Card controls spacing; otherwise we get double dividers.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          item.question,
          style: AppText.cardHeader(size: 14),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedAlignment: Alignment.centerLeft,
        children: [
          Text(
            item.answer,
            style: AppText.bodySecondary(size: 13).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FaqCategory {
  final String title;
  final IconData icon;
  final Color tint;
  final List<_FaqItem> items;

  const _FaqCategory({
    required this.title,
    required this.icon,
    required this.tint,
    required this.items,
  });
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}