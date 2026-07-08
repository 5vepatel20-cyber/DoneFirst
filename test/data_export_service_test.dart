import 'package:flutter_test/flutter_test.dart';
import 'package:donefirst/services/data_export_service.dart';

void main() {
  test('exportVersion is a non-empty semantic-version-ish string', () {
    // We bump this string on non-additive schema changes. Bumping it
    // is a deliberate decision; the test guards against accidental
    // mutation (e.g. someone "fixing" the formatting).
    expect(DataExportService.exportVersion, isNotEmpty);
    expect(DataExportService.exportVersion, matches(RegExp(r'^\d+\.\d+$')));
  });
}