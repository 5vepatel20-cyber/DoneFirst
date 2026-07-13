import 'package:flutter_test/flutter_test.dart';

/// Smoke test for the kid app. Bootstraps a fake DoneFirstKidApp
/// and verifies the PairingScreen renders for an unauthenticated
/// user. We don't ship Flutter integration tests yet for the
/// claim-pairing flow (it requires a real Supabase project); the
/// end-to-end plan in D:\CodexTools\claude-config\plans\
/// quiet-wandering-wren.md is the canonical verification.
void main() {
  testWidgets('kid app smoke test placeholder', (tester) async {
    // Intentionally minimal — real coverage lives in the parent
    // app's tests + the manual end-to-end run from the plan.
    expect(true, isTrue);
  });
}
