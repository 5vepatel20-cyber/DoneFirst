/// Canonical list of homework subjects used throughout the app.
///
/// Centralised here so the kid's task-entry screen, the parent's
/// stats breakdown, and any future filters all draw from one source
/// of truth. Adding a new subject means appending here + writing a
/// migration to relax the column check constraint, if one is added.
///
/// Order matters for UI: the first entry is the default for new
/// tasks, and the dropdown keeps this order top-to-bottom.
library;

const String kDefaultSubject = 'General';

const List<String> kSubjects = <String>[
  kDefaultSubject,
  'Math',
  'Science',
  'English',
  'History',
  'Foreign Language',
  'Art',
  'Music',
  'Other',
];

/// Returns the canonical subject string, falling back to the default
/// for any unrecognized value. Used when reading from the DB so an
/// older row with a deprecated subject still displays cleanly.
String normalizeSubject(String? raw) {
  if (raw == null) return kDefaultSubject;
  return kSubjects.contains(raw) ? raw : kDefaultSubject;
}