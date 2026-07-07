import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: 'https://wxjtksxugsirpowptpmz.supabase.co',
    publishableKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind4anRrc3h1Z3NpcnBvd3B0cG16Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMzMzMzMTgsImV4cCI6MjA5ODkwOTMxOH0.Ng9onu4901Q1yY0YnrM1XLyo5yOBoQbUariFqG-M3go',
  );
}
