import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class TimetableService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<UploadTask?> pickAndUpload({required String uuid}) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      type: FileType.custom,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final fileName = file.name;
    final destination = 'timetables/$uuid/${DateTime.now().millisecondsSinceEpoch}_${p.basename(fileName)}';

    if (kIsWeb || file.bytes != null) {
      final data = file.bytes!;
      return _storage.ref(destination).putData(data);
    }

    final path = file.path;
    if (path == null) {
      return null;
    }

    return _storage.ref(destination).putFile(File(path));
  }
}
