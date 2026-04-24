import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/book.dart';
import 'epub_library_service.dart';
import 'pdf_service.dart';

class BookService {
  static const String _booksBasePath = 'assets/books';
  static const List<String> _knownBooks = ['story_1'];
  static Future<List<Book>>? _inFlightLoad;
  static List<Book>? _cachedBooks;
  final EpubLibraryService _epubLibraryService = EpubLibraryService();
  final PdfService _pdfService = PdfService();

  Future<List<Book>> loadAllBooks({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedBooks != null) {
      return List<Book>.from(_cachedBooks!);
    }

    if (!forceRefresh && _inFlightLoad != null) {
      final books = await _inFlightLoad!;
      return List<Book>.from(books);
    }

    final loadFuture = _loadAllBooksImpl();
    _inFlightLoad = loadFuture;

    try {
      final books = await loadFuture;
      _cachedBooks = List<Book>.unmodifiable(books);
      return List<Book>.from(_cachedBooks!);
    } finally {
      if (identical(_inFlightLoad, loadFuture)) {
        _inFlightLoad = null;
      }
    }
  }

  void invalidateCache() {
    _cachedBooks = null;
    _inFlightLoad = null;
  }

  Future<List<Book>> _loadAllBooksImpl() async {
    final books = <Book>[];

    final imageBooksFuture = Future.wait(
      _knownBooks.map((bookId) async {
        try {
          return await loadBook(bookId);
        } catch (e) {
          print('Error loading book $bookId: $e');
          return null;
        }
      }),
    );

    final results = await Future.wait([
      imageBooksFuture,
      _epubLibraryService.loadLibraryBooks(),
      _pdfService.loadImportedPdfs(),
    ]);

    final imageBooks = results[0] as List<Book?>;
    final epubBooks = results[1] as List<Book>;
    final pdfBooks = results[2] as List<Book>;

    books.addAll(imageBooks.whereType<Book>());
    books.addAll(epubBooks);
    books.addAll(pdfBooks);

    return books;
  }

  Future<Book?> loadBook(String bookId) async {
    try {
      final manifestPath = '$_booksBasePath/$bookId/manifest.json';
      final manifestString = await rootBundle.loadString(manifestPath);
      final manifest = json.decode(manifestString) as Map<String, dynamic>;

      final title = manifest['title'] as String? ?? 'Untitled';
      final author = manifest['author'] as String?;
      final pageCount = manifest['pages'] as int? ?? 0;

      final pages = <PageAsset>[];
      for (int i = 1; i <= pageCount; i++) {
        pages.add(
          PageAsset(
            pageNumber: i,
            imagePath:
                '$_booksBasePath/$bookId/page_${i.toString().padLeft(3, '0')}.png',
          ),
        );
      }

      return Book(id: bookId, title: title, author: author, pages: pages);
    } catch (e) {
      print('Error loading book $bookId: $e');
      return null;
    }
  }
}
