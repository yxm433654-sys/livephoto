import 'dart:io';

class UserErrorMessage {
  const UserErrorMessage._();

  static String from(Object error) {
    final raw = error.toString().trim();
    final normalized = raw.startsWith('Exception: ')
        ? raw.substring('Exception: '.length).trim()
        : raw;
    final lower = normalized.toLowerCase();

    if (error is SocketException ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable')) {
      return '无法连接服务器，请检查网络和接口地址设置。';
    }

    if (error is HttpException ||
        lower.contains('connection closed before full header was received') ||
        lower.contains('connection reset')) {
      return '服务器连接已断开，请稍后重试。';
    }

    if (lower.contains('timeout') || lower.contains('timed out')) {
      return '请求超时，请检查网络状态后重试。';
    }

    if (lower.contains('websocket') ||
        lower.contains('stomp') ||
        lower.contains('sockjs')) {
      return '消息连接异常，正在尝试恢复连接。';
    }

    if (normalized.isEmpty) {
      return '操作失败，请稍后重试。';
    }

    return normalized;
  }
}
