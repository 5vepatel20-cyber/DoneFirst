import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../mistral_config.dart';

class ProofService {
  final _supabase = Supabase.instance.client;

  Future<String> uploadImage(File image, String taskId) async {
    final bytes = await image.readAsBytes();
    final ext = image.path.split('.').last;
    final path = 'proofs/$taskId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _supabase.storage
        .from('proof-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: 'image/$ext'),
        );
    final url = _supabase.storage.from('proof-photos').getPublicUrl(path);
    return url;
  }

  Future<Map<String, dynamic>> verifyWithMistral(
    String imageUrl,
    String taskDescription,
  ) async {
    try {
      final requestBody = jsonEncode({
        'model': MistralConfig.model,
        'response_format': {'type': 'json_object'},
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'You verify homework proof photos. Task: $taskDescription. Is this photo valid proof? Return JSON: {"decision": "approved"|"needs_review"|"rejected", "confidence": 0.0-1.0, "reason": "short reason"}',
              },
              {'type': 'image_url', 'image_url': imageUrl},
            ],
          },
        ],
      });

      final response = await http.post(
        Uri.parse(MistralConfig.apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${MistralConfig.apiKey}',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices']?[0]?['message']?['content'] ?? '';
        return jsonDecode(text);
      }
      return {
        'decision': 'needs_review',
        'confidence': 0.0,
        'reason': 'AI check failed',
      };
    } catch (e) {
      return {
        'decision': 'needs_review',
        'confidence': 0.0,
        'reason': 'Error: $e',
      };
    }
  }

  Future<Map<String, dynamic>> submitProof({
    required String taskId,
    required File image,
    required String taskDescription,
    String? note,
  }) async {
    final imageUrl = await uploadImage(image, taskId);
    final aiResult = await verifyWithMistral(imageUrl, taskDescription);

    final response = await _supabase
        .from('proof_submissions')
        .insert({
          'task_id': taskId,
          'image_url': imageUrl,
          'optional_note': note,
          'ai_decision': aiResult['decision'],
          'ai_confidence': (aiResult['confidence'] as num?)?.toDouble(),
          'ai_reason': aiResult['reason'],
          'parent_decision': 'pending',
        })
        .select()
        .single();

    if (aiResult['decision'] == 'approved') {
      await _supabase
          .from('homework_tasks')
          .update({'status': 'submitted'})
          .eq('id', taskId);
    }

    return {'proof': response, 'ai': aiResult};
  }

  Future<List<Map<String, dynamic>>> getProofsForSession(
    String sessionId,
  ) async {
    final tasks = await _supabase
        .from('homework_tasks')
        .select()
        .eq('session_id', sessionId);
    final proofs = <Map<String, dynamic>>[];
    for (final task in tasks) {
      final taskProofs = await _supabase
          .from('proof_submissions')
          .select()
          .eq('task_id', task['id'])
          .order('created_at', ascending: false);
      for (final proof in taskProofs) {
        proof['task_description'] = task['description'];
        proofs.add(proof);
      }
    }
    return proofs;
  }

  Future<void> updateParentDecision(
    String proofId,
    String decision, {
    String? parentNote,
  }) async {
    await _supabase
        .from('proof_submissions')
        .update({
          'parent_decision': decision,
          'parent_acted_at': DateTime.now().toIso8601String(),
          if (parentNote != null) 'parent_note': parentNote,
        })
        .eq('id', proofId);
  }

  Future<void> addTask(
    String sessionId,
    String description, {
    String subject = 'General',
  }) async {
    await _supabase.from('homework_tasks').insert({
      'session_id': sessionId,
      'description': description,
      'subject': subject,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> getTasks(String sessionId) async {
    final response = await _supabase
        .from('homework_tasks')
        .select()
        .eq('session_id', sessionId)
        .order('id');
    return response;
  }

  Future<void> deleteTask(String taskId) async {
    await _supabase.from('homework_tasks').delete().eq('id', taskId);
  }

  Future<void> deleteProof(String proofId) async {
    await _supabase.from('proof_submissions').delete().eq('id', proofId);
  }

  Future<Map<String, dynamic>?> getLatestProof(String taskId) async {
    final proofs = await _supabase
        .from('proof_submissions')
        .select()
        .eq('task_id', taskId)
        .order('created_at', ascending: false)
        .limit(1);
    return proofs.isNotEmpty ? proofs.first : null;
  }
}
