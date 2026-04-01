import 'package:vox_flutter/models/chat_session_summary.dart';
import 'package:vox_flutter/services/network/api_client.dart';

class SessionService {
  SessionService(this._api);

  final ApiClient _api;

  Future<List<ChatSessionSummary>> list({
    required int userId,
  }) async {
    final res = await _api.get<List<ChatSessionSummary>>(
      '/api/session/list',
      query: {'userId': userId.toString()},
      decode: (raw) {
        if (raw is! List) return <ChatSessionSummary>[];
        return raw
            .map(ChatSessionSummary.fromJson)
            .whereType<ChatSessionSummary>()
            .toList();
      },
    );
    if (!res.success) {
      throw Exception(res.message ?? 'Load sessions failed');
    }
    return res.data ?? <ChatSessionSummary>[];
  }
}
