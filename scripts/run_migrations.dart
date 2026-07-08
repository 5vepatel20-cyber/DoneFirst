import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  print('=== DoneFirst Schema Migrations ===\n');

  final supabaseUrl = Platform.environment['SUPABASE_URL'];
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (supabaseUrl == null || serviceRoleKey == null) {
    print('ERROR: Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars.');
    print('');
    print('Example:');
    print(r'  $env:SUPABASE_URL="https://wxjtksxugsirpowptpmz.supabase.co"');
    print(r'  $env:SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"');
    print('  dart run scripts/run_migrations.dart');
    print('');
    print('Get your service_role_key at:');
    print('  https://supabase.com/dashboard/project/wxjtksxugsirpowptpmz/settings/api');
    exit(1);
  }

  final ref = supabaseUrl.replaceAll('https://', '').replaceAll('.supabase.co', '');
  final url = Uri.parse('https://api.supabase.com/v1/projects/$ref/sql');

  final migrations = _loadMigrations();

  for (int i = 0; i < migrations.length; i++) {
    final sql = migrations[i];
    print('Running migration ${i + 1}/${migrations.length}...');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $serviceRoleKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': sql}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('  ✓ Migration ${i + 1} complete');
      } else {
        print('  ✗ Migration ${i + 1} failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('  ✗ Migration ${i + 1} error: $e');
    }
  }

  print('\nAll migrations complete!');
}

List<String> _loadMigrations() {
  final file = File('${Directory.current.path}/schema_migrations.sql');
  if (!file.existsSync()) {
    print('ERROR: schema_migrations.sql not found at ${file.path}');
    exit(1);
  }
  final content = file.readAsStringSync();
  final statements = <String>[];
  var current = '';
  for (final line in content.split('\n')) {
    if (line.trim().startsWith('--')) continue;
    current += '$line\n';
    if (line.trim().endsWith(';')) {
      statements.add(current.trim());
      current = '';
    }
  }
  if (current.trim().isNotEmpty) statements.add(current.trim());
  return statements;
}
