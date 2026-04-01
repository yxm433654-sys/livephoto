import 'package:vox_flutter/services/network/api_client.dart';
import 'package:vox_flutter/services/auth/auth_service.dart';
import 'package:vox_flutter/services/attachment/attachment_service.dart';
import 'package:vox_flutter/services/message/message_service.dart';
import 'package:vox_flutter/services/session/session_service.dart';

class AppServiceBundle {
  const AppServiceBundle({
    required this.apiClient,
    required this.authService,
    required this.messageService,
    required this.sessionService,
    required this.attachmentService,
  });

  final ApiClient apiClient;
  final AuthService authService;
  final MessageService messageService;
  final SessionService sessionService;
  final AttachmentService attachmentService;
}


