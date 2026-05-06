import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'app_storage_service.dart';

class EpubExtractor {
  static final EpubExtractor _instance = EpubExtractor._internal();
  factory EpubExtractor() => _instance;
  EpubExtractor._internal();

  final Map<String, String> _extractedPaths = {};

  Future<String> extractEpub(
    String sourceKey,
    List<int> epubBytes, {
    String? bookId,
  }) async {
    if (_extractedPaths.containsKey(sourceKey)) {
      final existingPath = _extractedPaths[sourceKey]!;
      if (await Directory(existingPath).exists()) {
        return existingPath;
      }
    }

    try {
      final appDir = await AppStorageService.documentsDirectory();
      final resolvedBookId = bookId ?? path.basenameWithoutExtension(sourceKey);
      final extractDir = path.join(appDir.path, 'epubs', resolvedBookId);

      final dir = Directory(extractDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);

      final archive = ZipDecoder().decodeBytes(epubBytes);

      for (final file in archive) {
        final filePath = path.join(extractDir, file.name);
        
        if (file.isFile) {
          final outputFile = File(filePath);
          await outputFile.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      _extractedPaths[sourceKey] = extractDir;
      print('Extracted EPUB to: ' + extractDir);
      return extractDir;
    } catch (e) {
      print('Error extracting EPUB: ' + e.toString());
      rethrow;
    }
  }

  Future<String> getFileContent(String extractDir, String filePath) async {
    final fullPath = path.join(extractDir, filePath);
    final file = File(fullPath);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  Future<List<int>> getFileBytes(String extractDir, String filePath) async {
    final fullPath = path.join(extractDir, filePath);
    final file = File(fullPath);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return [];
  }

  Future<void> cleanup(String sourceKey) async {
    if (_extractedPaths.containsKey(sourceKey)) {
      final dir = Directory(_extractedPaths[sourceKey]!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      _extractedPaths.remove(sourceKey);
    }
  }

  Future<void> cleanupBook(String bookId) async {
    final appDir = await AppStorageService.documentsDirectory();
    final dir = Directory(path.join(appDir.path, 'epubs', bookId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    _extractedPaths.removeWhere((_, value) => path.basename(value) == bookId);
  }

  Future<void> cleanupAll() async {
    for (final extractDir in _extractedPaths.values) {
      final dir = Directory(extractDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    _extractedPaths.clear();
  }
}
