# Migrations

Applied by hand through the Supabase SQL editor, in filename order.
There is no migration-tracking table, so **which ones are live is not
recorded anywhere** — the only way to know is to check the schema.

Every migration here is written to be idempotent, so when in doubt,
re-running is the safe move.

## ⚠️ Two numbers are used twice

`ls` sorts these correctly, but "run migration 20" is ambiguous — there
are two of them, they do unrelated things, and running one is easy to
mistake for running both:

| number | files |
|---|---|
| **17** | `migration_17_enable_realtime_kid_tables.sql`<br>`migration_17_kid_homework_sessions_rls.sql` |
| **20** | `migration_20_fix_proof_submissions_parent_delete_rls.sql`<br>`migration_20_kid_read_recurring_schedules.sql` |

They are left as-is rather than renumbered, because renumbering a file
that may already be applied to production makes the ambiguity worse,
not better. New migrations should keep going up from 23.

## Verifying what's actually applied

Table shape and policies are the source of truth. Quick checks:

```sql
-- Columns of a table
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'notifications'
ORDER BY ordinal_position;

-- Policies on a table
SELECT policyname, cmd, roles FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'proof_submissions';

-- Realtime publication members
SELECT tablename FROM pg_publication_tables
WHERE pubname = 'supabase_realtime' ORDER BY 1;
```

RLS is worth checking from the *client* side too, because a missing
policy does not raise: PostgREST answers `200 []`. Running the same
query with a kid's JWT and a parent's JWT is how you tell "no rows" from
"no access".

## 22 and 23 — pending as of 2026-07-29

Both were exercised against a throwaway Postgres 15 before being
proposed: applied to a database seeded with the foreign `notifications`
shape, re-applied to check idempotency, and probed with kid/parent/anon
JWT claims to confirm each policy allows and denies what it should.

- **`migration_22_restore_notifications_table.sql`** — restores the
  `notifications` table the app has always used. Non-destructive: a
  foreign `notifications` (one without `parent_id`) is *renamed* to
  `notifications_foreign_20260729`, never dropped. Re-running against an
  already-correct table leaves it and its rows untouched.

  Rows lost when the table was originally replaced are **not** recovered
  by this migration. Restore from a PITR snapshot first if they matter.

- **`migration_23_recurring_schedules_day_of_week_check.sql`** — pins
  `day_of_week` to `DateTime.weekday` (Mon=1..Sun=7). Self-aborts with a
  `NOTICE` instead of failing if any existing row is outside 1..7; if
  that fires, map `0 → 7` and shift `1..6` up by one, then re-run.
