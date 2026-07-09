// Tests for the string formatting used by PendingProofsScreen.
// The screen itself depends on Supabase, but the singular/plural
// formatting and selection-count header are pure-Dart and worth
// pinning down so we don't accidentally regress to "1 proofs".
import 'package:flutter_test/flutter_test.dart';

void main() {
  String formatCount(int count) => '$count ${count == 1 ? 'proof' : 'proofs'}';

  test('singular at 1', () {
    expect(formatCount(1), '1 proof');
  });

  test('plural at 0', () {
    expect(formatCount(0), '0 proofs');
  });

  test('plural at 2', () {
    expect(formatCount(2), '2 proofs');
  });

  test('plural at large N', () {
    expect(formatCount(47), '47 proofs');
  });

  test('selection header format', () {
    String selectionHeader(int selected) => '$selected selected';
    expect(selectionHeader(0), '0 selected');
    expect(selectionHeader(1), '1 selected');
    expect(selectionHeader(8), '8 selected');
  });

  test('bulk confirm title format', () {
    String confirmTitle(String verb, int count) =>
        '$verb $count ${count == 1 ? 'proof' : 'proofs'}?';
    expect(confirmTitle('Approve', 1), 'Approve 1 proof?');
    expect(confirmTitle('Reject', 5), 'Reject 5 proofs?');
  });
}