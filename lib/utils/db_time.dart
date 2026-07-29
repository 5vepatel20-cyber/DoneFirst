/// Timestamps written to Postgres.
///
/// Every timestamp column in this schema is `timestamptz`, and
/// PostgREST runs with the connection timezone set to UTC. A naive
/// ISO-8601 string — which is exactly what `DateTime.now()
/// .toIso8601String()` produces, because a local DateTime carries no
/// offset suffix — is therefore *read as UTC* by the server. On a
/// machine at UTC-4 that silently shifts every value four hours into
/// the past.
///
/// That is not theoretical. `SessionService.endSession` wrote
/// `ended_at` this way while `started_at` came from the column's
/// `DEFAULT now()` (correct UTC), so a real session recorded on
/// 2026-07-28 came back with `ended_at` 12:32 and `started_at` 14:32
/// — the session appeared to end two hours before it began. Anything
/// deriving a duration from the pair got a negative number, and the
/// kid's "focused today" tile silently fell back to the planned lock
/// length instead of the real one. The same shift made pairing codes
/// (`expires_at`) and approved breaks (`break_ends_at`) expire hours
/// early.
///
/// Use these helpers for anything crossing into the database — both
/// values being written and bounds in `.gte()` / `.lte()` filters.
/// `DateTime.toUtc()` emits the trailing `Z`, which PostgREST parses
/// as an absolute instant regardless of server timezone.
library;

/// Current instant, formatted for a `timestamptz` column.
String dbNow() => DateTime.now().toUtc().toIso8601String();

/// [time] formatted for a `timestamptz` column or filter bound.
String dbTime(DateTime time) => time.toUtc().toIso8601String();
