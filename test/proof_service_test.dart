import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/proof_service.dart';

/// Unit tests for ProofService.retryOnce.
///
/// The helper is the safety net behind every proof image upload
/// and AI-result fetch that goes through the Supabase storage
/// layer. A misbehaving retry (e.g. infinite loop, or swallowing
/// the final error) would either hang the parent UI or silently
/// drop proof photos, so we drive the function with controllable
/// fakes that exercise the success and failure paths.
void main() {
  group('ProofService.retryOnce', () {
    test('returns immediately on first success', () async {
      var calls = 0;
      final result = await ProofService.retryOnce<int>(
        () async {
          calls++;
          return 42;
        },
      );
      expect(calls, 1);
      expect(result, 42);
    });

    test('retries once on failure and returns second attempt result', () async {
      var calls = 0;
      final result = await ProofService.retryOnce<String>(
        () async {
          calls++;
          if (calls == 1) throw StateError('transient');
          return 'ok';
        },
        backoff: Duration.zero,
      );
      expect(calls, 2);
      expect(result, 'ok');
    });

    test('throws the final error after maxAttempts', () async {
      var calls = 0;
      Object? caught;
      try {
        await ProofService.retryOnce<void>(
          () async {
            calls++;
            throw StateError('boom $calls');
          },
          backoff: Duration.zero,
        );
      } catch (e) {
        caught = e;
      }
      expect(calls, 2);
      expect(caught, isA<StateError>());
      expect(caught.toString(), contains('boom 2'));
    });

    test('respects custom maxAttempts', () async {
      var calls = 0;
      try {
        await ProofService.retryOnce<void>(
          () async {
            calls++;
            throw StateError('nope');
          },
          backoff: Duration.zero,
          maxAttempts: 4,
        );
      } catch (_) {}
      expect(calls, 4);
    });
  });
}
