import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
    final response = await http.post(
      Uri.parse(
          'https://wxjtksxugsirpowptpmz.supabase.co/functions/v1/verify-proof'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_supabase.auth.currentSession?.accessToken ?? ''}',
      },
      body: jsonEncode({
        'imageUrl': imageUrl,
      }),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      return AiResult.fromJson(body);
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
    if (proofIds.isEmpty) return;
    final update = {
      'parent_decision': decision,
      'parent_acted_at': DateTime.now().toIso8601String(),
      if (parentNote != null) 'parent_note': parentNote,
    };
    // One update for the whole batch instead of one per ID. The
    // pending_proofs_screen can pass up to a few dozen at once, so
    // this turns a worst-case N-query storm into a single round-trip.
    await _supabase
        .from('proof_submissions')
        .update(update)
        .inFilter('id', proofIds);
  }

  /// Pending proofs for a child across all their sessions. A proof is
  /// pending when parent_decision = 'pending'.
  ///
  /// Joins through homework_tasks -> homework_sessions so we filter on
  /// the session's child_id (NOT on `homework_tasks.session_id`, which
  /// is the session's primary key — that would match proofs whose
  /// task belongs to a session whose id happens to equal the child
  /// id, which is almost never true and would silently return wrong
  /// rows).
  Future<List<ProofSubmission>> getPendingProofs(String childId) async {
    final response = await _supabase
        .from('proof_submissions')
        .select(
          '*, homework_tasks!inner(description, session_id,'
          ' homework_sessions!inner(child_id))',
        )
        .eq('parent_decision', 'pending')
        .eq('homework_tasks.homework_sessions.child_id', childId)
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
    // One query for the whole batch. The previous implementation
    // fired one SELECT per task — for a session with N tasks that's
    // N+1 round-trips including the task-id lookup in
    // getProofsForSession. Order by created_at desc so the newest
    // proof within the batch still surfaces first.
    final response = await _supabase
        .from('proof_submissions')
        .select()
        .inFilter('task_id', taskIds)
        .order('created_at', ascending: false);
    return response.map((m) => ProofSubmission.fromMap(m)).toList();
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
    // Single retry on transient failures. A second attempt clears
    // the common "connection reset mid-upload" case without
    // doubling the worst-case wait when the network is truly down
    // (the caller wraps this in a 60s timeout so the user gets
    // an error UI in O(timeout), not O(retries × timeout)).
    await retryOnce(
      () => _supabase.storage.from('proof-photos').uploadBinary(
            path,
            Uint8List.fromList(bytes),
          ),
    );
    final signedUrl = await retryOnce(
      () => _supabase.storage
          .from('proof-photos')
          .createSignedUrl(path, 604800),
    );
    return signedUrl;
  }

  /// Retries `op` once on failure with a small linear backoff.
  ///
  /// Static so the proof-screen flow and tests can exercise the
  /// exact retry semantics without spinning up a real Supabase
  /// client. Two attempts (not three) because the call site already
  /// wraps this in a 60 s timeout — the goal is to clear
  /// single-packet loss, not to mask a dead network.
  @visibleForTesting
  static Future<T> retryOnce<T>(
    Future<T> Function() op, {
    Duration backoff = const Duration(milliseconds: 250),
    int maxAttempts = 2,
  }) async {
    Object? last;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await op();
      } catch (e) {
        last = e;
        if (attempt < maxAttempts) {
          await Future.delayed(backoff);
        }
      }
    }
    throw last!;
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
    // Proofs carry session_id directly (see ProofSubmission model),
    // so we can skip the task-id intermediate that the old code
    // used to do. One query instead of two.
    final response = await _supabase
        .from('proof_submissions')
        .select()
        .eq('session_id', sessionId)
        .order('created_at', ascending: false);
    return response.map((m) => ProofSubmission.fromMap(m)).toList();
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
    final response = await _supabase.from('proof_submissions').insert({
      'task_id': taskId,
      'image_url': imageUrls.isNotEmpty ? imageUrls.first : '',
      'image_urls': imageUrls,
      'optional_note': note,
      'parent_decision': 'pending',
    }).select().single();
    if (imageUrls.isNotEmpty) {
      final proof = ProofSubmission.fromMap(response);
      final aiResult = await verifyWithMistral(imageUrls.first);
      await storeAiResult(proof.id, aiResult);
    }
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

  /// Number of Mistral verification calls this parent has made since
  /// midnight UTC. Used by the daily-cap UI on the parent dashboard.
  ///
  /// Counts rows in mistral_verification_log where called_at is in
  /// the last 24h. RLS already restricts the SELECT to this parent,
  /// so a parent cannot see another family's usage.
  Future<int> getMistralCallsToday() async {
    final parentId = _supabase.auth.currentUser?.id;
    if (parentId == null) return 0;
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(hours: 24))
        .toIso8601String();
    final response = await _supabase
        .from('mistral_verification_log')
        .select('id')
        .eq('parent_id', parentId)
        .gte('called_at', since);
    return (response as List).length;
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

}
