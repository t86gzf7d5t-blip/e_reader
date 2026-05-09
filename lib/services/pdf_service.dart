import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:pdfx/pdfx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import 'app_storage_service.dart';

class PdfService {
  static const String _registryPrefsKey = 'pdf_library_registry_v1';
  static const String _deletedSeedPrefsKey =
      'pdf_library_deleted_seed_assets_v1';
  static const String _bundledPdfAssetDirectory = 'assets/imported/';

  Future<List<Book>> loadImportedPdfs() async {
    await _seedBundledPdfsIfNeeded();

    final entries = await _loadEntries();
    final books = <Book>[];

    for (final entry in entries) {
      final book = await loadPdf(
        entry.originalFilePath,
        bookId: entry.id,
        canDelete: true,
      );
      if (book != null) {
        books.add(book);
      }
    }

    return books;
  }

  Future<Book?> importFromFilesystem() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final selectedPath = result.files.single.path;
    if (selectedPath == null) {
      return null;
    }

    final sourceFile = File(selectedPath);
    if (!await sourceFile.exists()) {
      return null;
    }

    final registry = await _loadEntries();
    final baseName = path.basenameWithoutExtension(selectedPath);
    final bookId = _buildUniqueBookId(baseName, registry);
    final originalsDir = await _ensureOriginalsDirectory();
    final originalFilePath = path.join(originalsDir.path, '$bookId.pdf');

    await sourceFile.copy(originalFilePath);

    registry.add(
      _PdfLibraryEntry(
        id: bookId,
        originalFilePath: originalFilePath,
        addedAt: DateTime.now(),
      ),
    );
    await _saveEntries(registry);

    return loadPdf(originalFilePath, bookId: bookId, canDelete: true);
  }

  Future<void> deleteBook(Book book) async {
    final registry = await _loadEntries();
    final entryIndex = registry.indexWhere((entry) => entry.id == book.id);
    if (entryIndex == -1) {
      return;
    }

    final entry = registry.removeAt(entryIndex);
    await _saveEntries(registry);

    if (!entry.originalFilePath.startsWith('assets/')) {
      final originalFile = File(entry.originalFilePath);
      if (await originalFile.exists()) {
        await originalFile.delete();
      }
    }

    if (entry.seedAssetPath != null) {
      final deletedSeeds = await _loadDeletedSeedAssets();
      if (!deletedSeeds.contains(entry.seedAssetPath)) {
        deletedSeeds.add(entry.seedAssetPath!);
        await _saveDeletedSeedAssets(deletedSeeds);
      }
    }
  }

  Future<Book?> loadPdf(
    String sourcePath, {
    String? bookId,
    bool canDelete = false,
  }) async {
    try {
      if (sourcePath.startsWith('assets/')) {
        await rootBundle.load(sourcePath);
      } else {
        final file = File(sourcePath);
        if (!await file.exists()) {
          return null;
        }
      }

      final resolvedBookId =
          bookId ?? path.basenameWithoutExtension(sourcePath);
      final title = path
          .basenameWithoutExtension(sourcePath)
          .replaceAll('_', ' ')
          .replaceAll('-', ' ');
      final coverPath = await _cachedPdfCoverPath(resolvedBookId);
      if (coverPath == null) {
        unawaited(_ensurePdfCoverImage(sourcePath, resolvedBookId));
      }

      return Book(
        id: resolvedBookId,
        title: title,
        author: 'PDF Document',
        coverPath: coverPath,
        originalFilePath: sourcePath,
        pages: [PageAsset(pageNumber: 1, imagePath: sourcePath)],
        isEpub: false,
        isPdf: true,
        canDelete: canDelete,
      );
    } catch (e) {
      print('Error loading PDF $sourcePath: $e');
      return null;
    }
  }

  Future<String?> _cachedPdfCoverPath(String bookId) async {
    final appDir = await AppStorageService.documentsDirectory();
    final coverFile = File(
      path.join(appDir.path, 'library', 'pdf_covers', '$bookId.png'),
    );
    return await coverFile.exists() ? coverFile.path : null;
  }

  Future<String?> _ensurePdfCoverImage(String sourcePath, String bookId) async {
    PdfDocument? document;
    try {
      final pdfPath = sourcePath.startsWith('assets/')
          ? await _copyBundledPdfToStorage(sourcePath)
          : sourcePath;

      final appDir = await AppStorageService.documentsDirectory();
      final coverDir = Directory(
        path.join(appDir.path, 'library', 'pdf_covers'),
      );
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }

      final coverFile = File(path.join(coverDir.path, '$bookId.png'));
      final sourceFile = File(pdfPath);
      if (await coverFile.exists() &&
          await sourceFile.exists() &&
          coverFile.lastModifiedSync().isAfter(sourceFile.lastModifiedSync())) {
        return coverFile.path;
      }

      document = await PdfDocument.openFile(pdfPath);
      final page = await document.getPage(1);
      try {
        final image = await page.render(
          width: page.width * 0.5,
          height: page.height * 0.5,
          format: PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        final bytes = image?.bytes;
        if (bytes == null) {
          return null;
        }
        await coverFile.writeAsBytes(bytes, flush: true);
        return coverFile.path;
      } finally {
        await page.close();
      }
    } catch (e) {
      print('Error generating PDF cover $sourcePath: $e');
      return null;
    } finally {
      await document?.close();
    }
  }

  Future<String> _copyBundledPdfToStorage(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final appDir = await AppStorageService.documentsDirectory();
    final pdfDir = Directory(path.join(appDir.path, 'library', 'bundled_pdfs'));
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }

    final outputFile = File(path.join(pdfDir.path, path.basename(assetPath)));
    final expectedLength = data.lengthInBytes;
    if (!await outputFile.exists() ||
        await outputFile.length() != expectedLength) {
      await outputFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, expectedLength),
        flush: true,
      );
    }
    return outputFile.path;
  }

  Future<void> _seedBundledPdfsIfNeeded() async {
    final registry = await _loadEntries();
    final deletedSeeds = await _loadDeletedSeedAssets();
    final bundledAssets = await _discoverBundledPdfAssets();
    final bundledAssetSet = bundledAssets
        .map((asset) => asset.toLowerCase())
        .toSet();
    var changed = false;

    registry.removeWhere((entry) {
      final seedAssetPath = entry.seedAssetPath;
      if (seedAssetPath == null) {
        return false;
      }

      final isStale = !bundledAssetSet.contains(seedAssetPath.toLowerCase());
      if (isStale) {
        changed = true;
      }
      return isStale;
    });

    for (final assetPath in bundledAssets) {
      final normalizedAssetPath = assetPath.toLowerCase();
      if (deletedSeeds.contains(normalizedAssetPath)) {
        continue;
      }

      final existingIndex = registry.indexWhere(
        (entry) => entry.seedAssetPath?.toLowerCase() == normalizedAssetPath,
      );
      if (existingIndex == -1) {
        registry.add(
          _PdfLibraryEntry(
            id: _normalizeId(path.basenameWithoutExtension(assetPath)),
            originalFilePath: assetPath,
            seedAssetPath: normalizedAssetPath,
            addedAt: DateTime.now(),
          ),
        );
        changed = true;
      } else if (!registry[existingIndex].originalFilePath.startsWith(
        'assets/',
      )) {
        registry[existingIndex] = _PdfLibraryEntry(
          id: registry[existingIndex].id,
          originalFilePath: assetPath,
          seedAssetPath: normalizedAssetPath,
          addedAt: registry[existingIndex].addedAt,
        );
        changed = true;
      }
    }

    if (changed) {
      await _saveEntries(registry);
    }
  }

  Future<List<String>> _discoverBundledPdfAssets() async {
    final discovered = <String>{};

    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final assetPath in manifest.listAssets()) {
        final decodedPath = Uri.decodeFull(assetPath);
        if (decodedPath.startsWith(_bundledPdfAssetDirectory) &&
            decodedPath.toLowerCase().endsWith('.pdf')) {
          discovered.add(decodedPath);
        }
      }
    } catch (e) {
      print('[PdfService] asset-manifest-scan-failed: $e');
    }

    return discovered.toList()..sort();
  }

  Future<Directory> _ensureOriginalsDirectory() async {
    final appDir = await AppStorageService.documentsDirectory();
    final directory = Directory(path.join(appDir.path, 'library', 'pdfs'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<List<_PdfLibraryEntry>> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries = prefs.getString(_registryPrefsKey);
    if (rawEntries == null || rawEntries.isEmpty) {
      return [];
    }

    final decoded = json.decode(rawEntries) as List<dynamic>;
    final entries = decoded
        .map(
          (entry) => _PdfLibraryEntry.fromJson(entry as Map<String, dynamic>),
        )
        .toList();

    entries.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return entries;
  }

  Future<void> _saveEntries(List<_PdfLibraryEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _registryPrefsKey,
      json.encode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<List<String>> _loadDeletedSeedAssets() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_deletedSeedPrefsKey) ?? <String>[];
  }

  Future<void> _saveDeletedSeedAssets(List<String> deletedSeeds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_deletedSeedPrefsKey, deletedSeeds);
  }

  String _buildUniqueBookId(String baseName, List<_PdfLibraryEntry> entries) {
    final normalized = _normalizeId(baseName);
    final existingIds = entries.map((entry) => entry.id).toSet();

    if (!existingIds.contains(normalized)) {
      return normalized;
    }

    return '$normalized-${DateTime.now().millisecondsSinceEpoch}';
  }

  String _normalizeId(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');

    return normalized.isEmpty
        ? 'pdf-${DateTime.now().millisecondsSinceEpoch}'
        : normalized;
  }
}

class _PdfLibraryEntry {
  final String id;
  final String originalFilePath;
  final String? seedAssetPath;
  final DateTime addedAt;

  const _PdfLibraryEntry({
    required this.id,
    required this.originalFilePath,
    required this.addedAt,
    this.seedAssetPath,
  });

  factory _PdfLibraryEntry.fromJson(Map<String, dynamic> json) {
    return _PdfLibraryEntry(
      id: json['id'] as String,
      originalFilePath: json['originalFilePath'] as String,
      seedAssetPath: json['seedAssetPath'] as String?,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalFilePath': originalFilePath,
      'seedAssetPath': seedAssetPath,
      'addedAt': addedAt.toIso8601String(),
    };
  }
}
