import 'package:shared_preferences/shared_preferences.dart';

/// Per-parent notification preferences.
///
/// Stored in SharedPreferences for now (single device per parent).
/// When we move to multi-device support, this should migrate to a
/// column on the `parents` table backed by RLS.
class NotificationPreferencesService {
  static const String _storageKey = 'notif_prefs_v1';

  /// Notification types we know about. Each entry is metadata so the
  /// settings UI can render without holding its own labels.
  ///
  /// When you add a new notification type in `NotificationService`:
  ///   1. Add a constant here with its storage key + human label
  ///   2. Optionally set [defaultEnabled] to false if you think most
  ///      parents will want it off
  ///   3. Reference it from [defaultPrefs] below
  static const String typeProofSubmitted = 'proof_submitted';
  static const String typeBreakRequested = 'break_requested';
  static const String typeSessionComplete = 'session_complete';

  /// All known types in display order. The settings UI iterates this.
  static const List<NotificationPrefSpec> specs = [
    NotificationPrefSpec(
      type: typeProofSubmitted,
      label: 'New proof submitted',
      description:
          "When your child takes a photo of their completed homework.",
      defaultEnabled: true,
    ),
    NotificationPrefSpec(
      type: typeBreakRequested,
      label: 'Break requests',
      description: 'When your child asks for a break during a lock.',
      defaultEnabled: true,
    ),
    NotificationPrefSpec(
      type: typeSessionComplete,
      label: 'Session complete',
      description:
          'When a homework session finishes (success or cancelled).',
      defaultEnabled: true,
    ),
  ];

  /// Returns the default preferences — every known type enabled.
  static Map<String, bool> defaultPrefs() => {
        for (final spec in specs) spec.type: spec.defaultEnabled,
      };

  /// Read the current preferences. Missing keys fall back to defaults
  /// so adding a new type while a user is on an older build still
  /// gives a sensible answer.
  Future<Map<String, bool>> getPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey);
    final defaults = defaultPrefs();
    if (stored == null) return defaults;
    // Stored format: "type=enabled" per entry, so we can keep order
    // and parse easily.
    final result = Map<String, bool>.from(defaults);
    for (final entry in stored) {
      final parts = entry.split('=');
      if (parts.length != 2) continue;
      result[parts[0]] = parts[1] == '1';
    }
    return result;
  }

  /// True if [type] should generate notifications right now.
  Future<bool> isEnabled(String type) async {
    final prefs = await getPrefs();
    return prefs[type] ?? true;
  }

  /// Set one preference and persist. Setting to the default value
  /// still writes, so we can detect "user changed then reverted" and
  /// surface their revert in tests.
  Future<void> setEnabled(String type, bool enabled) async {
    final current = await getPrefs();
    current[type] = enabled;
    await _persist(current);
  }

  /// Reset everything to defaults (all enabled).
  Future<void> resetToDefaults() async {
    await _persist(defaultPrefs());
  }

  Future<void> _persist(Map<String, bool> prefs) async {
    final storage = await SharedPreferences.getInstance();
    final encoded = prefs.entries
        .map((e) => '${e.key}=${e.value ? '1' : '0'}')
        .toList();
    await storage.setStringList(_storageKey, encoded);
  }
}

/// Metadata for a single notification-type preference.
class NotificationPrefSpec {
  final String type;
  final String label;
  final String description;
  final bool defaultEnabled;

  const NotificationPrefSpec({
    required this.type,
    required this.label,
    required this.description,
    required this.defaultEnabled,
  });
}
