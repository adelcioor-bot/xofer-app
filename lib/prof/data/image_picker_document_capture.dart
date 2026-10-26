import 'package:image_picker/image_picker.dart';
import 'package:xofer/prof/domain/document_capture.dart';
import 'package:xofer/prof/domain/provider_account.dart';

class ImagePickerDocumentCapture implements DocumentCapture {
  ImagePickerDocumentCapture({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CapturedDocument?> pick(DocumentSource source) async {
    final file = await _picker.pickImage(
      source: source == DocumentSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return null;
    return CapturedDocument(name: file.name, bytes: await file.readAsBytes());
  }
}
