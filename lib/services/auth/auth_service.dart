import 'package:vox_flutter/models/session.dart';
import 'package:vox_flutter/models/user.dart';
import 'package:vox_flutter/services/network/api_client.dart';

class AuthService {
  AuthService(this._api);

  final ApiClient _api;

  Future<Session> login(
      {required String username, required String password}) async {
    final res = await _api.postJson<Map<String, dynamic>>(
      '/api/user/login',
      body: {'username': username, 'password': password},
      decode: (raw) => (raw as Map).cast<String, dynamic>(),
    );
    if (!res.success || res.data == null) {
      throw Exception(res.message ?? 'Login failed');
    }
    final data = res.data!;
    return Session(
      userId: (data['userId'] as num).toInt(),
      username: data['username']?.toString() ?? username,
      token: data['token']?.toString() ?? '',
      expiresAt: data['expiresAt'] is String
          ? DateTime.tryParse(data['expiresAt'])
          : null,
    );
  }

  Future<UserProfile> register({
    required String username,
    required String password,
    String? avatarUrl,
  }) async {
    final res = await _api.postJson<Object?>(
      '/api/user/register',
      body: {
        'username': username,
        'password': password,
        'avatarUrl': avatarUrl
      },
      decode: (raw) => raw,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'Register failed');
    }
    return UserProfile.fromJson(res.data);
  }

  Future<UserProfile> getUser(int userId) async {
    final res = await _api.get<Object?>(
      '/api/user/$userId',
      decode: (raw) => raw,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'Get user failed');
    }
    return UserProfile.fromJson(res.data);
  }

  Future<UserProfile> getUserByUsername(String username) async {
    final res = await _api.get<Object?>(
      '/api/user/by-username',
      query: {'username': username},
      decode: (raw) => raw,
    );
    if (!res.success) {
      throw Exception(res.message ?? 'Search user failed');
    }
    return UserProfile.fromJson(res.data);
  }
}
