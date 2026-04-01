import 'package:vox_flutter/application/session/app_service_bundle.dart';
import 'package:vox_flutter/services/network/api_client.dart';
import 'package:vox_flutter/services/auth/auth_service.dart';
import 'package:vox_flutter/services/attachment/attachment_service.dart';
import 'package:vox_flutter/services/message/message_service.dart';
import 'package:vox_flutter/services/session/session_service.dart';

class ServiceBundleFactory {
  const ServiceBundleFactory();

  AppServiceBundle build({
    required String apiBaseUrl,
  }) {
    final apiClient = ApiClient(baseUrl: apiBaseUrl);
    return AppServiceBundle(
      apiClient: apiClient,
      authService: AuthService(apiClient),
      messageService: MessageService(apiClient),
      sessionService: SessionService(apiClient),
      attachmentService: AttachmentService(baseUrl: apiBaseUrl),
    );
  }
}
