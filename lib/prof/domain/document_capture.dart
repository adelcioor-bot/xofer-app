import 'package:xofer/prof/domain/provider_account.dart';

enum DocumentSource { camera, gallery }

abstract class DocumentCapture {
  Future<CapturedDocument?> pick(DocumentSource source);
}
