import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import 'app_storage_service.dart';
import 'epub_extractor.dart';
import 'epub_service.dart';

class EpubLibraryService {
  static const String _registryPrefsKey = 'epub_library_registry_v1';
  static const String _deletedSeedPrefsKey =
      'epub_library_deleted_seed_assets_v1';
  static const int _metadataLoadBatchSize = 3;
  static const Duration _metadataTimeout = Duration(seconds: 12);

  // Keep this list small and stable so every build has a predictable starter shelf.
  static const List<String> _starterSeedAssets = [
    'assets/imported/pg11-images-3.epub',
    'assets/imported/pg14838-images-3.epub',
    'assets/imported/pg37106-images-3.epub',
    'assets/imported/pg12-images-3.epub',
    'assets/imported/pg55-images-3.epub',
    'assets/imported/pg84-images-3.epub',
    'assets/imported/pg100-images-3.epub',
    'assets/imported/pg1342-images-3.epub',
  ];

  // Add gift-ready built-in books here. They are seeded once, then behave like imports.
  static const List<String> _giftSeedAssets = [];

  final EpubService _epubService = EpubService();
  final EpubExtractor _extractor = EpubExtractor();

  Future<List<Book>> loadLibraryBooks() async {
    print('[EpubLibrary] load-start');
    await _seedBundledBooksIfNeeded();

    final entries = await _loadEntries();
    print(
      '[EpubLibrary] registry entries=${entries.length} ids=${entries.map((entry) => '${entry.id}:${entry.originalFilePath}').join(',')}',
    );
    final books = <Book>[];

    for (var i = 0; i < entries.length; i += _metadataLoadBatchSize) {
      final batch = entries.skip(i).take(_metadataLoadBatchSize).toList();
      final loadedBatch = await Future.wait(
        batch.map((entry) async {
          try {
            return await _epubService
                .loadEpubFileMetadataOnly(
                  entry.originalFilePath,
                  bookId: entry.id,
                  canDelete: true,
                )
                .timeout(
                  _metadataTimeout,
                  onTimeout: () {
                    print('Timed out loading EPUB metadata ${entry.originalFilePath}');
                    return _fallbackBookForEntry(entry);
                  },
                );
          } catch (e) {
            print('Error loading library EPUB ${entry.originalFilePath}: $e');
            return null;
          }
        }),
      );

      for (final book in loadedBatch) {
        if (book != null) {
          books.add(book);
        }
      }
      print('[EpubLibrary] loaded-so-far=${books.length}/${entries.length}');
    }

    print('[EpubLibrary] load-complete books=${books.length}');
    return books;
  }

  Future<Book?> importFromFilesystem() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
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
    final originalFilePath = path.join(originalsDir.path, '$bookId.epub');

    await sourceFile.copy(originalFilePath);

    registry.add(
      _LibraryBookEntry(
        id: bookId,
        originalFilePath: originalFilePath,
        addedAt: DateTime.now(),
      ),
    );
    await _saveEntries(registry);

    return _epubService.loadEpubFileMetadataOnly(
      originalFilePath,
      bookId: bookId,
      canDelete: true,
    );
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

    await _extractor.cleanupBook(entry.id);

    if (entry.seedAssetPath != null) {
      final deletedSeeds = await _loadDeletedSeedAssets();
      if (!deletedSeeds.contains(entry.seedAssetPath)) {
        deletedSeeds.add(entry.seedAssetPath!);
        await _saveDeletedSeedAssets(deletedSeeds);
      }
    }
  }

  Future<void> _seedBundledBooksIfNeeded() async {
    final registry = await _loadEntries();
    final deletedSeeds = await _loadDeletedSeedAssets();
    var changed = false;
    print(
      '[EpubLibrary] seed-start registry=${registry.length} deleted=${deletedSeeds.length}',
    );

    for (final assetPath in [..._starterSeedAssets, ..._giftSeedAssets]) {
      final normalizedAssetPath = assetPath.toLowerCase();

      final existingIndex = registry.indexWhere(
        (entry) => entry.seedAssetPath?.toLowerCase() == normalizedAssetPath,
      );
      if (deletedSeeds.contains(normalizedAssetPath)) {
        continue;
      }

      final bookId = path.basenameWithoutExtension(assetPath);
      if (existingIndex == -1) {
        print('[EpubLibrary] seed-add $bookId -> $assetPath');
        registry.add(
          _LibraryBookEntry(
            id: bookId,
            originalFilePath: assetPath,
            seedAssetPath: normalizedAssetPath,
            addedAt: DateTime.now(),
          ),
        );
        changed = true;
      } else if (!registry[existingIndex].originalFilePath.startsWith('assets/')) {
        print(
          '[EpubLibrary] seed-migrate ${registry[existingIndex].id} -> $assetPath',
        );
        registry[existingIndex] = _LibraryBookEntry(
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
    print('[EpubLibrary] seed-complete registry=${registry.length} changed=$changed');
  }

  Book _fallbackBookForEntry(_LibraryBookEntry entry) {
    final title = path
        .basenameWithoutExtension(entry.originalFilePath)
        .replaceAll('_', ' ')
        .replaceAll('-', ' ');

    return Book(
      id: entry.id,
      title: title,
      author: 'Unknown',
      originalFilePath: entry.originalFilePath,
      isEpub: true,
      canDelete: true,
    );
  }

  Future<Directory> _ensureOriginalsDirectory() async {
    final appDir = await AppStorageService.documentsDirectory();
    final directory = Directory(path.join(appDir.path, 'library', 'originals'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<List<_LibraryBookEntry>> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final rawEntries = prefs.getString(_registryPrefsKey);
    if (rawEntries == null || rawEntries.isEmpty) {
      return [];
    }

    final decoded = json.decode(rawEntries) as List<dynamic>;
    final entries = decoded
        .map((entry) => _LibraryBookEntry.fromJson(entry as Map<String, dynamic>))
        .toList();

    entries.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return entries;
  }

  Future<void> _saveEntries(List<_LibraryBookEntry> entries) async {
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

  String _buildUniqueBookId(String baseName, List<_LibraryBookEntry> entries) {
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
        ? 'book-${DateTime.now().millisecondsSinceEpoch}'
        : normalized;
  }
}

class _LibraryBookEntry {
  final String id;
  final String originalFilePath;
  final String? seedAssetPath;
  final DateTime addedAt;

  const _LibraryBookEntry({
    required this.id,
    required this.originalFilePath,
    required this.addedAt,
    this.seedAssetPath,
  });

  factory _LibraryBookEntry.fromJson(Map<String, dynamic> json) {
    return _LibraryBookEntry(
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
