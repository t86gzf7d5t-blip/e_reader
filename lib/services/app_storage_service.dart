import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppStorageService {
  static const String _androidPackageName = 'com.example.e_reader';

  static Future<Directory> documentsDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      print('[AppStorage] path_provider documents failed: $e');
      return _fallbackDirectory();
    }
  }

  static Future<Directory> _fallbackDirectory() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('No storage fallback for ${Platform.operatingSystem}');
    }

    final directory = Directory('/data/data/$_androidPackageName/files');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    print('[AppStorage] using Android fallback directory: ${directory.path}');
    return directory;
  }
}
