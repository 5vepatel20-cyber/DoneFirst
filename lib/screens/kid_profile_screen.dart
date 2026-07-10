import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/models.dart';
import '../services/session_service.dart';
import '../theme/app_theme.dart';

final List<Color> kidColors = [
  AppColors.primary,
  AppColors.accent,
  AppColors.success,
  AppColors.info,
  AppColors.danger,
  AppColors.warning,
  const Color(0xFFE91E63),
  const Color(0xFF00BCD4),
];

const List<String> kidEmojis = [
  '🧑',
  '👧',
  '👦',
  '🧒',
  '👩',
  '👨',
  '🧑‍🎓',
  '🌟',
];

class KidProfileScreen extends StatefulWidget {
  final Child child;

  const KidProfileScreen({super.key, required this.child});

  @override
  State<KidProfileScreen> createState() => _KidProfileScreenState();
}

class _KidProfileScreenState extends State<KidProfileScreen> {
  final _sessionService = SessionService();
  late TextEditingController _nameController;
  int _selectedColor = 0;
  int _selectedEmoji = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.child.name);
    if (widget.child.color != null) {
      // The color comes back as a base-16 string ("aabbccdd"-style
      // without the 0x prefix) — int.parse defaults to base-10 so
      // we need to pass radix: 16 explicitly.
      final parsed = int.tryParse(widget.child.color!, radix: 16);
      if (parsed != null) {
        final idx = kidColors.indexWhere(
          (c) => c.toARGB32() == Color(parsed).toARGB32(),
        );
        if (idx >= 0) _selectedColor = idx;
      }
    }
    if (widget.child.emoji != null) {
      final idx = kidEmojis.indexOf(widget.child.emoji!);
      if (idx >= 0) _selectedEmoji = idx;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = _nameController.text.trim();
      if (name.isNotEmpty && name != widget.child.name) {
        await _sessionService.renameChild(widget.child.id, name);
      }
      await _sessionService.updateChildProfile(
        widget.child.id,
        color: kidColors[_selectedColor].toARGB32().toRadixString(16),
        emoji: kidEmojis[_selectedEmoji],
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final childName = widget.child.name;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.x, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('$childName\'s profile', style: AppText.screenTitle()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: kidColors[_selectedColor].withValues(alpha:0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  kidEmojis[_selectedEmoji],
                  style: const TextStyle(fontSize: 44),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              childName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(LucideIcons.user, size: 18),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Color Theme',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: List.generate(
              kidColors.length,
              (i) => GestureDetector(
                onTap: () => setState(() => _selectedColor = i),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kidColors[i],
                    shape: BoxShape.circle,
                    border: _selectedColor == i
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: _selectedColor == i
                        ? [
                            BoxShadow(
                              color: kidColors[i].withValues(alpha:0.5),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Avatar',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              kidEmojis.length,
              (i) => GestureDetector(
                onTap: () => setState(() => _selectedEmoji = i),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _selectedEmoji == i
                        ? kidColors[_selectedColor].withValues(alpha:0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: _selectedEmoji == i
                        ? Border.all(color: kidColors[_selectedColor], width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      kidEmojis[_selectedEmoji],
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.check, size: 16),
            label: const Text('Save Profile'),
          ),
        ],
      ),
    );
  }
}
