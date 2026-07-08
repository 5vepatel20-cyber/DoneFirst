import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Seed script: creates test data in Supabase.
/// Usage:
///   $env:SUPABASE_URL="https://wxjtksxugsirpowptpmz.supabase.co"
///   $env:SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
///   dart run scripts/seed_data.dart <parent_email> <parent_password>
void main(List<String> args) async {
  final supabaseUrl = Platform.environment['SUPABASE_URL'] ??
      'https://wxjtksxugsirpowptpmz.supabase.co';
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (serviceRoleKey == null) {
    print('ERROR: Set SUPABASE_SERVICE_ROLE_KEY env var.');
    exit(1);
  }

  if (args.length < 2) {
    print('Usage: dart run scripts/seed_data.dart <email> <password>');
    print('This will create a test parent account with sample children/sessions.');
    exit(1);
  }

  final email = args[0];
  final password = args[1];
  final ref = supabaseUrl.replaceAll('https://', '').replaceAll('.supabase.co', '');

  // 1. Sign up via Auth API
  print('Creating parent account...');
  final authRes = await http.post(
    Uri.parse('$supabaseUrl/auth/v1/signup'),
    headers: {
      'apikey': serviceRoleKey,
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'email': email,
      'password': password,
    }),
  );
  if (authRes.statusCode != 200 && authRes.statusCode != 201) {
    print('Signup failed: ${authRes.body}');
    print('(User may already exist — continuing to seed data)');
  }
  final userId = authRes.statusCode == 200
      ? jsonDecode(authRes.body)['id'] as String?
      : null;
  if (userId == null) {
    print('Could not get user ID. Try creating user in Supabase Auth UI.');
    exit(1);
  }

  void runSql(String sql) {
    http.post(
      Uri.parse('https://api.supabase.com/v1/projects/$ref/sql'),
      headers: {
        'Authorization': 'Bearer $serviceRoleKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'query': sql}),
    );
  }

  // 2. Create parent record
  print('Creating parent record...');
  runSql("""
    INSERT INTO parents (id, email, display_name)
    VALUES ('$userId', '$email', 'Test Parent')
    ON CONFLICT (id) DO UPDATE SET email = '$email';
  """);

  // 3. Create family
  print('Creating family...');
  runSql("""
    INSERT INTO families (name) VALUES ('Smith Family')
    RETURNING id;
  """);
  // Get the family ID via direct insert
  final famRes = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/families'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({'name': 'Smith Family'}),
  );
  if (famRes.statusCode != 201) {
    print('Family creation failed: ${famRes.body}');
    exit(1);
  }
  final familyId = jsonDecode(famRes.body)[0]['id'] as String;

  // Link parent to family
  runSql("""
    UPDATE parents SET family_id = '$familyId' WHERE id = '$userId';
  """);

  // 4. Create 2 children
  print('Creating children...');
  final child1Res = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/children'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({
      'family_id': familyId,
      'name': 'Alice',
      'color': 'blue',
      'emoji': '👧',
    }),
  );
  final child1Id = jsonDecode(child1Res.body)[0]['id'] as String;

  await http.post(
    Uri.parse('$supabaseUrl/rest/v1/children'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({
      'family_id': familyId,
      'name': 'Bob',
      'color': 'green',
      'emoji': '👦',
    }),
  );

  // 5. Create a completed session for Alice
  print('Creating sample sessions...');
  final sesRes = await http.post(
    Uri.parse('$supabaseUrl/rest/v1/homework_sessions'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: jsonEncode({
      'child_id': child1Id,
      'parent_id': userId,
      'status': 'completed',
      'started_at': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      'ended_at': DateTime.now().subtract(const Duration(hours: 23)).toIso8601String(),
      'min_lock_minutes': 60,
    }),
  );
  final sessionId = jsonDecode(sesRes.body)[0]['id'] as String;

  // 6. Create tasks for the session
  print('Creating tasks...');
  await http.post(
    Uri.parse('$supabaseUrl/rest/v1/homework_tasks'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'session_id': sessionId,
      'description': 'Math worksheet p.42-45',
      'subject': 'Math',
      'status': 'approved',
    }),
  );
  await http.post(
    Uri.parse('$supabaseUrl/rest/v1/homework_tasks'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'session_id': sessionId,
      'description': 'Read Chapter 3 of The Giver',
      'subject': 'Reading',
      'status': 'approved',
    }),
  );

  // 7. Create a recurring schedule
  print('Creating schedule...');
  await http.post(
    Uri.parse('$supabaseUrl/rest/v1/recurring_schedules'),
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      'child_id': child1Id,
      'day_of_week': DateTime.now().weekday - 1,
      'duration_minutes': 60,
      'approval_mode': 'balanced',
    }),
  );

  print('\n✓ Seed complete!');
  print('  Parent: $email / $password');
  print('  Family: Smith Family ($familyId)');
  print('  Children: Alice 👧, Bob 👦');
  print('  Completed session + tasks created for Alice');
  print('  Recurring schedule set for today');
}
