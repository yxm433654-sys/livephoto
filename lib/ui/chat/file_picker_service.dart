import 'package:file_picker/file_picker.dart';

class FilePickerService {
  const FilePickerService._();

  static Future<List<PlatformFile>> pickFiles({
    int maxCount = 9,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: false,
    );
    if (result == null) {
      return const <PlatformFile>[];
    }
    final files = result.files.where((file) => (file.path ?? '').isNotEmpty).toList();
    if (files.length <= maxCount) {
      return files;
    }
    return files.take(maxCount).toList();
  }
}
