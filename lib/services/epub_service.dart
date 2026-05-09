import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../models/book.dart';
import 'app_storage_service.dart';
import 'epub_extractor.dart';

/// Extracts EPUB files and lets EPUB.js handle rendering inside the reader.
class EpubService {
  final EpubExtractor _extractor = EpubExtractor();

  Future<Book?> loadEpubAsset(
    String assetPath, {
    bool canDelete = false,
  }) async {
    try {
      print('Loading EPUB asset: $assetPath');

      final bytes = await rootBundle.load(assetPath);
      final epubBytes = bytes.buffer.asUint8List();
      final bookId = path.basenameWithoutExtension(assetPath);

      return _loadExtractedEpub(
        sourceKey: assetPath,
        bookId: bookId,
        epubBytes: epubBytes,
        fallbackTitle: bookId,
        canDelete: canDelete,
      );
    } catch (e, stackTrace) {
      print('Error loading EPUB asset: $e');
      print(stackTrace);
      return null;
    }
  }

  Future<Book?> loadEpubFile(
    String filePath, {
    required String bookId,
    bool canDelete = true,
  }) async {
    try {
      print('Loading EPUB file: $filePath');
      final epubBytes = await File(filePath).readAsBytes();

      return _loadExtractedEpub(
        sourceKey: filePath,
        bookId: bookId,
        epubBytes: epubBytes,
        fallbackTitle: path.basenameWithoutExtension(filePath),
        canDelete: canDelete,
      );
    } catch (e, stackTrace) {
      print('Error loading EPUB file: $e');
      print(stackTrace);
      return null;
    }
  }

  Future<Book?> loadEpubFileMetadataOnly(
    String filePath, {
    required String bookId,
    bool canDelete = true,
  }) async {
    try {
      print('Loading EPUB metadata only: $filePath');
      final epubBytes = filePath.startsWith('assets/')
          ? (await rootBundle.load(filePath)).buffer.asUint8List()
          : await File(filePath).readAsBytes();
      print(
        '[EpubService] metadata-bytes bookId=$bookId bytes=${epubBytes.length} source=$filePath',
      );
      final archive = ZipDecoder().decodeBytes(epubBytes);
      final unsupportedReason = _detectUnsupportedReason(archive);
      final containerXml = _readArchiveText(archive, 'META-INF/container.xml');
      if (containerXml == null) {
        return Book(
          id: bookId,
          title: path.basenameWithoutExtension(filePath),
          author: 'Unknown',
          isEpub: true,
          canDelete: canDelete,
          originalFilePath: filePath,
          unsupportedReason: unsupportedReason,
        );
      }

      final opfPath = _extractOpfPath(containerXml);
      final opfContent = opfPath == null
          ? null
          : _readArchiveText(archive, opfPath);

      Map<String, String?> metadata = <String, String?>{};
      List<Chapter> chapters = <Chapter>[];

      if (opfPath != null && opfContent != null) {
        metadata = _parseMetadataFromOpf(opfContent, opfPath);
        chapters = _parseChaptersFromArchive(archive, opfPath, opfContent);
        try {
          final cachedCoverPath = await _extractCoverToCache(
            archive,
            bookId: bookId,
            internalCoverPath: metadata['coverPath'],
          );
          if (cachedCoverPath != null && cachedCoverPath.isNotEmpty) {
            metadata['coverPath'] = cachedCoverPath;
          }
        } catch (e) {
          print('[EpubService] cover-cache-skipped bookId=$bookId error=$e');
          metadata['coverPath'] = null;
        }
      }

      final book = Book(
        id: bookId,
        title: metadata['title'] ?? path.basenameWithoutExtension(filePath),
        author: metadata['author'] ?? 'Unknown',
        coverPath: metadata['coverPath'],
        originalFilePath: filePath,
        chapters: chapters,
        isEpub: true,
        canDelete: canDelete,
        unsupportedReason: unsupportedReason,
      );
      print(
        '[EpubService] metadata-complete bookId=$bookId title="${book.title}" chapters=${book.chapters.length}',
      );
      return book;
    } catch (e, stackTrace) {
      print('Error loading EPUB metadata only: $e');
      print(stackTrace);
      return null;
    }
  }

  Future<Book> ensureExtractedForReading(Book book) async {
    if (!book.isEpub) {
      return book;
    }

    if (!book.isSupported) {
      return book;
    }

    final existingExtractPath = book.extractPath;
    if (existingExtractPath != null &&
        await Directory(existingExtractPath).exists()) {
      return book;
    }

    final originalFilePath = book.originalFilePath;
    if (originalFilePath == null) {
      return book;
    }

    final extracted = originalFilePath.startsWith('assets/')
        ? await loadEpubAsset(originalFilePath, canDelete: book.canDelete)
        : await loadEpubFile(
            originalFilePath,
            bookId: book.id,
            canDelete: book.canDelete,
          );

    if (extracted == null) {
      return book;
    }

    return book.copyWith(
      extractPath: extracted.extractPath,
      coverPath: extracted.coverPath ?? book.coverPath,
      chapters: extracted.chapters.isNotEmpty
          ? extracted.chapters
          : book.chapters,
    );
  }

  Future<Book> _loadExtractedEpub({
    required String sourceKey,
    required String bookId,
    required List<int> epubBytes,
    required String fallbackTitle,
    required bool canDelete,
  }) async {
    final extractDir = await _extractor.extractEpub(
      sourceKey,
      epubBytes,
      bookId: bookId,
    );
    print('Extracted EPUB to: $extractDir');

    final metadata = await _parseMetadata(extractDir);
    final chapters = await _parseChapters(extractDir);

    print('Loaded book: ${metadata['title']} with ${chapters.length} chapters');

    return Book(
      id: bookId,
      title: metadata['title'] ?? fallbackTitle,
      author: metadata['author'] ?? 'Unknown',
      coverPath: _resolveCoverPath(extractDir, metadata['coverPath']),
      originalFilePath: sourceKey,
      extractPath: extractDir,
      chapters: chapters,
      isEpub: true,
      canDelete: canDelete,
    );
  }

  String? _extractOpfPath(String containerXml) {
    final rootfileMatch = RegExp(
      'full-path=["\']([^"\']+)["\']',
    ).firstMatch(containerXml);
    return rootfileMatch?.group(1);
  }

  String? _readArchiveText(Archive archive, String filePath) {
    final normalizedTarget = filePath.replaceAll('\\', '/').toLowerCase();
    for (final entry in archive) {
      final entryPath = entry.name.replaceAll('\\', '/').toLowerCase();
      if (!entry.isFile || entryPath != normalizedTarget) {
        continue;
      }

      final content = entry.content;
      if (content is List<int>) {
        return String.fromCharCodes(content);
      }
    }
    return null;
  }

  String? _detectUnsupportedReason(Archive archive) {
    final encryptionXml = _readArchiveText(archive, 'META-INF/encryption.xml');
    final rightsXml = _readArchiveText(archive, 'META-INF/rights.xml');
    final hasAdobeRights = rightsXml?.toLowerCase().contains('adobe') ?? false;
    final hasAdeptEncryption =
        encryptionXml?.toLowerCase().contains('http://ns.adobe.com/adept') ??
        false;
    final hasAesEncryption =
        encryptionXml?.toLowerCase().contains('aes128-cbc') ?? false;

    if (hasAdobeRights || hasAdeptEncryption || hasAesEncryption) {
      return 'This EPUB is DRM-protected and cannot be opened by Nectar & Sol. Please use a DRM-free EPUB file.';
    }

    return null;
  }

  Map<String, String?> _parseMetadataFromOpf(
    String opfContent,
    String opfPath,
  ) {
    final titleMatch = RegExp(
      '<dc:title[^>]*>([^<]+)</dc:title>',
      caseSensitive: false,
    ).firstMatch(opfContent);

    final authorMatch = RegExp(
      '<dc:creator[^>]*>([^<]+)</dc:creator>',
      caseSensitive: false,
    ).firstMatch(opfContent);

    String? coverPath;
    final coverIdMatch = RegExp(
      "<meta[^>]+name=['\"]cover['\"][^>]+content=['\"]([^'\"]+)['\"]",
      caseSensitive: false,
    ).firstMatch(opfContent);

    if (coverIdMatch != null) {
      final coverId = coverIdMatch.group(1)!;
      final manifestHref = _findManifestItemHrefById(opfContent, coverId);
      if (manifestHref != null) {
        coverPath = path.join(path.dirname(opfPath), manifestHref);
      }
    }

    final coverImageHref = _findCoverImageHref(opfContent);
    if (coverPath == null && coverImageHref != null) {
      coverPath = path.join(path.dirname(opfPath), coverImageHref);
    }

    return {
      'title': titleMatch?.group(1)?.trim(),
      'author': authorMatch?.group(1)?.trim(),
      'coverPath': coverPath,
    };
  }

  String? _findManifestItemHrefById(String opfContent, String itemId) {
    final itemRegex = RegExp('<item\\b[^>]*>', caseSensitive: false);

    for (final match in itemRegex.allMatches(opfContent)) {
      final tag = match.group(0)!;
      final id = _extractAttribute(tag, 'id');
      if (id != itemId) {
        continue;
      }

      return _extractAttribute(tag, 'href');
    }

    return null;
  }

  String? _findCoverImageHref(String opfContent) {
    final itemRegex = RegExp('<item\\b[^>]*>', caseSensitive: false);

    for (final match in itemRegex.allMatches(opfContent)) {
      final tag = match.group(0)!;
      final properties = _extractAttribute(tag, 'properties');
      if (properties == null ||
          !properties.toLowerCase().contains('cover-image')) {
        continue;
      }

      return _extractAttribute(tag, 'href');
    }

    return null;
  }

  String? _extractAttribute(String tag, String attributeName) {
    final match = RegExp(
      '$attributeName=[\'"]([^\'"]+)[\'"]',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }

  Future<String?> _extractCoverToCache(
    Archive archive, {
    required String bookId,
    required String? internalCoverPath,
  }) async {
    if (internalCoverPath == null || internalCoverPath.isEmpty) {
      return null;
    }

    final normalizedTarget = internalCoverPath
        .replaceAll('\\', '/')
        .toLowerCase();
    final normalizedBasename = path.basename(normalizedTarget);

    ArchiveFile? matchedEntry;
    for (final entry in archive) {
      final entryPath = entry.name.replaceAll('\\', '/').toLowerCase();
      if (!entry.isFile) {
        continue;
      }
      if (entryPath == normalizedTarget) {
        matchedEntry = entry;
        break;
      }
    }

    matchedEntry ??= archive.firstWhere(
      (entry) =>
          entry.isFile &&
          path.basename(entry.name.replaceAll('\\', '/').toLowerCase()) ==
              normalizedBasename,
      orElse: () => ArchiveFile('', 0, []),
    );

    if (!matchedEntry.isFile || matchedEntry.name.isEmpty) {
      matchedEntry = archive.firstWhere((entry) {
        if (!entry.isFile) {
          return false;
        }

        final entryPath = entry.name.replaceAll('\\', '/').toLowerCase();
        final extension = path.extension(entryPath);
        const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp'];
        return entryPath.contains('cover') &&
            imageExtensions.contains(extension);
      }, orElse: () => ArchiveFile('', 0, []));
    }

    if (!matchedEntry.isFile || matchedEntry.name.isEmpty) {
      return null;
    }

    final content = matchedEntry.content;
    if (content is! List<int>) {
      return null;
    }

    final appDir = await AppStorageService.documentsDirectory();
    final coversDir = Directory(path.join(appDir.path, 'library', 'covers'));
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final extension = path.extension(matchedEntry.name).toLowerCase();
    final safeExtension = extension.isEmpty ? '.jpg' : extension;
    final outputPath = path.join(coversDir.path, '$bookId$safeExtension');
    await File(outputPath).writeAsBytes(content, flush: true);
    print('Cached EPUB cover for $bookId at $outputPath');
    return outputPath;
  }

  String? _resolveCoverPath(String extractDir, String? coverPath) {
    if (coverPath == null || coverPath.isEmpty) {
      return null;
    }

    if (path.isAbsolute(coverPath)) {
      return coverPath;
    }

    return path.join(extractDir, coverPath);
  }

  List<Chapter> _parseChaptersFromArchive(
    Archive archive,
    String opfPath,
    String opfContent,
  ) {
    final chapters = <Chapter>[];
    final opfDir = path.dirname(opfPath);

    final ncxManifestMatch = RegExp(
      "<item[^>]+(?:media-type=['\"]application/x-dtbncx\\+xml['\"]|href=['\"]([^'\"]+\\.ncx)['\"])[^>]*href=['\"]([^'\"]+)['\"]",
      caseSensitive: false,
    ).firstMatch(opfContent);

    final ncxHref = ncxManifestMatch?.group(2) ?? ncxManifestMatch?.group(1);
    if (ncxHref != null) {
      final ncxPath = path.normalize(path.join(opfDir, ncxHref));
      final ncxContent = _readArchiveText(archive, ncxPath);
      if (ncxContent != null) {
        final navPointRegex = RegExp(
          '<navPoint[^>]*>.*?<text[^>]*>([^<]+)</text>.*?<content[^>]+src=["\']([^"\']+)["\']',
          caseSensitive: false,
          dotAll: true,
        );

        var order = 0;
        for (final match in navPointRegex.allMatches(ncxContent)) {
          chapters.add(
            Chapter(
              title: match.group(1)!.trim(),
              href: match.group(2)!,
              order: order++,
            ),
          );
        }
      }
    }

    if (chapters.isNotEmpty) {
      return chapters;
    }

    final navItemMatch = RegExp(
      "<item[^>]+properties=['\"][^'\"]*nav[^'\"]*['\"][^>]+href=['\"]([^'\"]+)['\"]",
      caseSensitive: false,
    ).firstMatch(opfContent);
    final navHref = navItemMatch?.group(1);
    if (navHref != null) {
      final navPath = path.normalize(path.join(opfDir, navHref));
      final navContent = _readArchiveText(archive, navPath);
      if (navContent != null) {
        final linkRegex = RegExp(
          '<a[^>]+href=["\']([^"\']+)["\'][^>]*>([^<]+)</a>',
          caseSensitive: false,
        );

        var order = 0;
        for (final match in linkRegex.allMatches(navContent)) {
          chapters.add(
            Chapter(
              title: match.group(2)!.trim(),
              href: match.group(1)!,
              order: order++,
            ),
          );
        }
      }
    }

    return chapters;
  }

  Future<Map<String, String?>> _parseMetadata(String extractDir) async {
    try {
      final containerPath = path.join(extractDir, 'META-INF', 'container.xml');
      final containerXml = await File(containerPath).readAsString();

      final opfPath = _extractOpfPath(containerXml);
      if (opfPath == null) {
        return {};
      }

      final opfFullPath = path.join(extractDir, opfPath);
      final opfContent = await File(opfFullPath).readAsString();
      return _parseMetadataFromOpf(opfContent, opfPath);
    } catch (e) {
      print('Error parsing metadata: $e');
      return {};
    }
  }

  Future<List<Chapter>> _parseChapters(String extractDir) async {
    final chapters = <Chapter>[];

    try {
      final ncxFiles = await Directory(extractDir)
          .list(recursive: true)
          .where((f) => f is File && f.path.toLowerCase().endsWith('.ncx'))
          .map((f) => f.path)
          .toList();

      if (ncxFiles.isNotEmpty) {
        final ncxContent = await File(ncxFiles.first).readAsString();
        final navPointRegex = RegExp(
          '<navPoint[^>]*>.*?<text[^>]*>([^<]+)</text>.*?<content[^>]+src=["\']([^"\']+)["\']',
          caseSensitive: false,
          dotAll: true,
        );

        var order = 0;
        for (final match in navPointRegex.allMatches(ncxContent)) {
          chapters.add(
            Chapter(
              title: match.group(1)!.trim(),
              href: match.group(2)!,
              order: order++,
            ),
          );
        }
      }

      if (chapters.isEmpty) {
        final navFiles = await Directory(extractDir)
            .list(recursive: true)
            .where((f) => f is File && f.path.toLowerCase().contains('nav'))
            .map((f) => f.path)
            .toList();

        if (navFiles.isNotEmpty) {
          final navContent = await File(navFiles.first).readAsString();
          final linkRegex = RegExp(
            '<a[^>]+href=["\']([^"\']+)["\'][^>]*>([^<]+)</a>',
            caseSensitive: false,
          );

          var order = 0;
          for (final match in linkRegex.allMatches(navContent)) {
            chapters.add(
              Chapter(
                title: match.group(2)!.trim(),
                href: match.group(1)!,
                order: order++,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error parsing chapters: $e');
    }

    return chapters;
  }
}
