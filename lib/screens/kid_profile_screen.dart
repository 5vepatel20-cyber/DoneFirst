import 'package:flutter/material.dart';
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
  final Map<String, dynamic> child;

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
    _nameController = TextEditingController(
      text: widget.child['name'] as String? ?? '',
    );
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
      if (name.isNotEmpty && name != widget.child['name']) {
        await _sessionService.renameChild(widget.child['id'], name);
      }
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
    final childName = widget.child['name'] as String? ?? 'Child';
    return Scaffold(
      appBar: AppBar(title: Text('$childName\'s Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: kidColors[_selectedColor].withOpacity(0.15),
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
              prefixIcon: Icon(Icons.person),
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
                              color: kidColors[i].withOpacity(0.5),
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
                        ? kidColors[_selectedColor].withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: _selectedEmoji == i
                        ? Border.all(color: kidColors[_selectedColor], width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      kidEmojis[i],
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
                : const Icon(Icons.save),
            label: const Text('Save Profile'),
          ),
        ],
      ),
    );
  }
}
