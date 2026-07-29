-- Migration 23: pin recurring_schedules.day_of_week to Mon=1..Sun=7.
--
-- The column had no constraint, so the two conventions the Dart code
-- was using could both "work" against it and nothing ever complained.
-- The day picker has always written DateTime.weekday (Mon=1..Sun=7),
-- but RecurringSchedule.dayName, RecurringSchedule.isToday,
-- ScheduleService.getTodaySchedules and the kid's next-session picker
-- all read it as Mon=0..Sun=6. The results were quiet and wrong:
--
--   * getTodaySchedules asked for weekday-1, so it matched the
--     previous day's schedules every day of the week
--   * Sunday schedules (7) were never matched at all — the query
--     asked for 6
--   * the schedule list card said "Wed" while the delete dialog for
--     the same row said "Delete … Thu schedule?" and required typing
--     "Thu (1h)" to confirm
--
-- The Dart side is now uniformly Mon=1..Sun=7. This constraint is
-- what keeps it that way: a writer that reverts to the 0-based
-- convention now fails loudly on Monday instead of silently
-- scheduling Sunday.
--
-- Idempotent, and refuses to fire if it would invalidate existing
-- rows — a migration that can't be applied is better than one that
-- takes the table's writes down with it.

DO $$
DECLARE
  bad_rows INT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'recurring_schedules_day_of_week_check'
  ) THEN
    RETURN;
  END IF;

  SELECT count(*) INTO bad_rows
  FROM recurring_schedules
  WHERE day_of_week IS NULL OR day_of_week < 1 OR day_of_week > 7;

  IF bad_rows > 0 THEN
    RAISE NOTICE
      'Skipping day_of_week CHECK: % row(s) outside 1..7. These were '
      'written with the old 0-based convention; map 0 -> 7 (Sunday) '
      'and shift 1..6 up by one before re-running.', bad_rows;
    RETURN;
  END IF;

  ALTER TABLE recurring_schedules
    ADD CONSTRAINT recurring_schedules_day_of_week_check
    CHECK (day_of_week BETWEEN 1 AND 7);
END $$;
