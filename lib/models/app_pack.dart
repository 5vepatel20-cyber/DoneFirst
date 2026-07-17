import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class AppPack {
  final String name;
  final String description;
  final List<String> apps;
  final IconData icon;

  const AppPack({
    required this.name,
    required this.description,
    required this.apps,
    required this.icon,
  });

  static const List<AppPack> defaults = [
    AppPack(
      name: 'Social Media',
      description: 'TikTok, Instagram, Snapchat, Facebook, X/Twitter',
      apps: [
        'TikTok',
        'Instagram',
        'Snapchat',
        'Facebook',
        'X',
        'Twitter',
        'WhatsApp',
      ],
      icon: LucideIcons.users,
    ),
    AppPack(
      name: 'Games',
      description: 'Roblox, Minecraft, Fortnite, Call of Duty, mobile games',
      apps: [
        'Roblox',
        'Minecraft',
        'Fortnite',
        'Call of Duty',
        'Candy Crush',
        'Subway Surfers',
      ],
      icon: LucideIcons.gamepad2,
    ),
    AppPack(
      name: 'Entertainment',
      description: 'YouTube, Netflix, Hulu, Disney+, Twitch',
      apps: [
        'YouTube',
        'Netflix',
        'Hulu',
        'Disney+',
        'Twitch',
        'HBO Max',
        'Amazon Prime Video',
      ],
      icon: LucideIcons.tv,
    ),
    AppPack(
      name: 'All Distractions',
      description: 'Everything social, games, and entertainment',
      apps: [
        'TikTok',
        'Instagram',
        'Snapchat',
        'Facebook',
        'YouTube',
        'Roblox',
        'Minecraft',
        'Netflix',
        'Twitch',
      ],
      icon: LucideIcons.ban,
    ),
  ];
}
