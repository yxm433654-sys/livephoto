class RealtimeRuntimeState {
  int _lastMessageId = 0;
  String? _connectionNotice;

  int get lastMessageId => _lastMessageId;
  String? get connectionNotice => _connectionNotice;

  bool updateLastMessageId(int nextValue) {
    if (nextValue <= _lastMessageId) {
      return false;
    }
    _lastMessageId = nextValue;
    return true;
  }

  void resetLastMessageId() {
    _lastMessageId = 0;
  }

  bool setConnectionNotice(String? nextNotice) {
    if (_connectionNotice == nextNotice) {
      return false;
    }
    _connectionNotice = nextNotice;
    return true;
  }

  void clearConnectionNotice() {
    _connectionNotice = null;
  }
}
