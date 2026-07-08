import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../mistral_config.dart';
import '../models/models.dart';

class ProofService {
  final _supabase = Supabase.instance.client;

  Future<ProofSubmission> uploadProof({
    required String taskId,
    required String imageUrl,
    required String kidNote,
    required String sessionId,
  }) async {
    final response = await _supabase
        .from('proof_submissions')
        .insert({
          'task_id': taskId,
          'session_id': sessionId,
          'image_url': imageUrl,
          'image_urls': [imageUrl],
          'optional_note': kidNote.isEmpty ? null : kidNote,
          'parent_decision': 'pending',
        })
        .select()
        .single();
    return ProofSubmission.fromMap(response);
  }

  Future<AiResult> verifyWithMistral(String imageUrl) async {
    final base64Image = await _downloadAndEncodeImage(imageUrl);
    final response = await http.post(
      Uri.parse(MistralConfig.apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${MistralConfig.apiKey}',
      },
      body: jsonEncode({
        'model': MistralConfig.model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text':
                    'You are verifying homework proof photos. Analyze the image and decide if it shows legitimate homework (worksheet, written answers, textbook, notes, computer screen with schoolwork). '
                    'If it looks like valid homework, respond with decision "approved". '
                    'If unclear or suspicious, respond with "needs_review". '
                    'If clearly not homework, respond with "rejected". '
                    'Respond in this JSON format ONLY: {"decision": "approved|needs_review|rejected", "confidence": 0.0-1.0, "reason": "brief explanation"}',
              },
              {
                'type': 'image_url',
                'image_url': 'data:image/jpeg;base64,$base64Image',
              },
            ],
          }
        ],
        'response_format': {'type': 'json_object'},
        'max_tokens': 256,
      }),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final content = body['choices']?[0]?['message']?['content'] ?? '{}';
      final resultJson = jsonDecode(content as String);
      return AiResult.fromJson(resultJson);
    }
    return AiResult(
      decision: 'needs_review',
      confidence: 0.0,
      reason: 'API error: ${response.statusCode}',
    );
  }

  Future<void> storeAiResult(
    String proofId,
    AiResult aiResult,
  ) async {
    await _supabase.from('proof_submissions').update({
      'ai_decision': aiResult.decision,
      'ai_confidence': aiResult.confidence,
      'ai_reason': aiResult.reason,
    }).eq('id', proofId);
  }

  Future<void> parentApprove(
    String proofId, {
    String? parentNote,
  }) async {
    await _supabase.from('proof_submissions').update({
      'parent_decision': 'approved',
      'parent_acted_at': DateTime.now().toIso8601String(),
      if (parentNote != null) 'parent_note': parentNote,
    }).eq('id', proofId);
  }

  Future<void> parentReject(
    String proofId, {
    String? parentNote,
  }) async {
    await _supabase.from('proof_submissions').update({
      'parent_decision': 'rejected',
      'parent_acted_at': DateTime.now().toIso8601String(),
      if (parentNote != null) 'parent_note': parentNote,
    }).eq('id', proofId);
  }

  Future<void> batchApproveOrReject(
    List<String> proofIds,
    String decision, {
    String? parentNote,
  }) async {
    final update = {
      'parent_decision': decision,
      'parent_acted_at': DateTime.now().toIso8601String(),
      if (parentNote != null) 'parent_note': parentNote,
    };
    for (final id in proofIds) {
      await _supabase
          .from('proof_submissions')
          .update(update)
          .eq('id', id);
    }
  }

  Future<List<ProofSubmission>> getPendingProofs(String childId) async {
    final response = await _supabase
        .from('proof_submissions')
        .select('*, homework_tasks!inner(description)')
        .eq('parent_decision', 'pending')
        .eq('homework_tasks.session_id', childId)
        .order('created_at', ascending: false);
    return response.map((m) {
      final p = ProofSubmission.fromMap(m);
      p.taskDescription = m['homework_tasks']?['description'] as String?;
      return p;
    }).toList();
  }

  Future<List<ProofSubmission>> getProofsForTasks(
    List<String> taskIds,
  ) async {
    if (taskIds.isEmpty) return [];
    final results = <ProofSubmission>[];
    for (final taskId in taskIds) {
      final response = await _supabase
          .from('proof_submissions')
          .select()
          .eq('task_id', taskId)
          .order('created_at', ascending: false);
      results.addAll(response.map((m) => ProofSubmission.fromMap(m)));
    }
    return results;
  }

  Future<ProofSubmission?> getProofForTask(String taskId) async {
    final response = await _supabase
        .from('proof_submissions')
        .select()
        .eq('task_id', taskId)
        .order('created_at', ascending: false)
        .limit(1);
    if (response.isEmpty) return null;
    return ProofSubmission.fromMap(response.first);
  }

  Future<String> uploadImageToStorage(
    String path,
    List<int> bytes,
  ) async {
    await _supabase.storage.from('proof-photos').uploadBinary(
          path,
          Uint8List.fromList(bytes),
        );
    return _supabase.storage.from('proof-photos').getPublicUrl(path);
  }

  Future<String> addImageToProof(String proofId, String imageUrl) async {
    final proof = await getProofForTask(proofId);
    if (proof == null) return '';
    final updatedUrls = [...proof.imageUrls, imageUrl];
    await _supabase
        .from('proof_submissions')
        .update({'image_urls': updatedUrls})
        .eq('id', proofId);
    return imageUrl;
  }

  Future<void> deleteProof(String proofId) async {
    await _supabase.from('proof_submissions').delete().eq('id', proofId);
  }

  Future<void> deleteTask(String taskId) async {
    await _supabase.from('proof_submissions').delete().eq('task_id', taskId);
    await _supabase.from('homework_tasks').delete().eq('id', taskId);
  }

  Future<List<ProofSubmission>> getProofsForSession(String sessionId) async {
    final tasks = await _supabase
        .from('homework_tasks')
        .select('id')
        .eq('session_id', sessionId);
    final taskIds = tasks.map((t) => t['id'] as String).toList();
    if (taskIds.isEmpty) return [];
    return getProofsForTasks(taskIds);
  }

  Future<String> uploadImage(dynamic img, String taskId) async {
    final bytes = await (img as dynamic).readAsBytes();
    final path = 'proofs/$taskId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    return uploadImageToStorage(path, bytes);
  }

  Future<void> submitProofWithUrls({
    required String taskId,
    required List<String> imageUrls,
    required String taskDescription,
    String? note,
  }) async {
    await _supabase.from('proof_submissions').insert({
      'task_id': taskId,
      'image_url': imageUrls.isNotEmpty ? imageUrls.first : '',
      'image_urls': imageUrls,
      'optional_note': note,
      'parent_decision': 'pending',
    });
  }

  Future<List<HomeworkTask>> getTasks(String sessionId) async {
    final response = await _supabase
        .from('homework_tasks')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: true);
    return response.map((m) => HomeworkTask.fromMap(m)).toList();
  }

  Future<HomeworkTask> addTask(
    String sessionId,
    String description, {
    String subject = 'General',
  }) async {
    final response = await _supabase
        .from('homework_tasks')
        .insert({
          'session_id': sessionId,
          'description': description,
          'subject': subject,
          'status': 'pending',
        })
        .select()
        .single();
    return HomeworkTask.fromMap(response);
  }

  Future<ProofSubmission?> getLatestProof(String taskId) async {
    return getProofForTask(taskId);
  }

  Future<void> updateParentDecision(
    String proofId,
    String decision, {
    String? parentNote,
  }) async {
    if (decision == 'approved') {
      await parentApprove(proofId, parentNote: parentNote);
    } else {
      await parentReject(proofId, parentNote: parentNote);
    }
  }

  Future<String> _downloadAndEncodeImage(String url) async {
    final response = await http.get(Uri.parse(url));
    return base64Encode(response.bodyBytes);
  }
}
