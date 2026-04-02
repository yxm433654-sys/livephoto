import 'package:shared_preferences/shared_preferences.dart';

class HiddenMessageStore {
  const HiddenMessageStore._();

  static String _key(int currentUserId, int peerId) =>
      'hidden_messages_${currentUserId}_$peerId';

  static Future<Set<int>> load({
    required int currentUserId,
    required int peerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(currentUserId, peerId)) ?? const <String>[];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> hide({
    required int currentUserId,
    required int peerId,
    required int messageId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(currentUserId, peerId);
    final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
    ids.add('$messageId');
    await prefs.setStringList(key, ids.toList()..sort());
  }
}
