import 'package:file_picker/file_picker.dart';

class FilePickerService {
  const FilePickerService._();

  static Future<FilePickerResult?> pickSingleFile() {
    return FilePicker.platform.pickFiles(withData: false);
  }
}
