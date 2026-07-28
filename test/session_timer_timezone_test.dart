import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:donefirst/widgets/session_timer.dart';

/// homework_sessions.started_at is a Postgres timestamptz, so
/// DateTime.parse hands the model back a *UTC* DateTime. SessionTimer
/// used to read .hour straight off it, which rendered a session begun
/// at 10:00 AM EDT as "Started 2:00 PM" — four hours in the future,
/// sitting right next to a countdown that was ticking correctly
/// (Duration maths is timezone-agnostic, so only the wall-clock
/// labels were wrong).
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Independent formatter, so the assertion doesn't just re-run the
  /// widget's own arithmetic.
  String clock(DateTime d) {
    final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  testWidgets('start/end labels use the device timezone, not UTC', (
    tester,
  ) async {
    final startUtc = DateTime.utc(2026, 7, 28, 14, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionTimer(
            sessionStart: startUtc,
            durationMinutes: 25,
            minUnlockMinutes: 25,
            autoLiftMinutes: 240,
          ),
        ),
      ),
    );

    final localStart = startUtc.toLocal();
    expect(find.text('Started ${clock(localStart)}'), findsOneWidget);
    expect(
      find.text('Ends ${clock(localStart.add(const Duration(minutes: 25)))}'),
      findsOneWidget,
    );

    // The chips share the same formatter, so they have to move too —
    // a half-converted screen is worse than a consistently wrong one.
    expect(
      find.text(
        'Min unlock: ${clock(localStart.add(const Duration(minutes: 25)))}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Auto-lift: ${clock(localStart.add(const Duration(minutes: 240)))}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a UTC-typed start is not rendered at its UTC hour', (
    tester,
  ) async {
    // Guards the actual regression rather than re-deriving it: unless
    // the test machine is itself on UTC, the displayed hour must
    // differ from the raw UTC hour.
    final startUtc = DateTime.utc(2026, 7, 28, 14, 0);
    if (startUtc.toLocal().hour == startUtc.hour) {
      return; // Machine is on UTC — nothing to distinguish.
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionTimer(sessionStart: startUtc, durationMinutes: 25),
        ),
      ),
    );

    expect(find.text('Started ${clock(startUtc)}'), findsNothing);
  });
}
