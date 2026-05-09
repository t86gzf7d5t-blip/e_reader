import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/book.dart';
import 'epub_library_service.dart';
import 'pdf_service.dart';

class BookService {
  static const String _booksBasePath = 'assets/books';
  static const List<String> _knownBooks = [];
  static Future<List<Book>>? _inFlightLoad;
  static List<Book>? _cachedBooks;
  final EpubLibraryService _epubLibraryService = EpubLibraryService();
  final PdfService _pdfService = PdfService();

  Future<List<Book>> loadAllBooks({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedBooks != null) {
      _logBookCounts('cache-hit', _cachedBooks!);
      return List<Book>.from(_cachedBooks!);
    }

    if (!forceRefresh && _inFlightLoad != null) {
      final books = await _inFlightLoad!;
      _logBookCounts('in-flight-hit', books);
      return List<Book>.from(books);
    }

    print('[BookService] load-start forceRefresh=$forceRefresh');
    final loadFuture = _loadAllBooksImpl();
    _inFlightLoad = loadFuture;

    try {
      final books = await loadFuture;
      _logBookCounts('load-complete', books);
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

    try {
      final imageBooks = await Future.wait(
        _knownBooks.map((bookId) async {
          try {
            return await loadBook(bookId);
          } catch (e) {
            print('Error loading book $bookId: $e');
            return null;
          }
        }),
      );
      books.addAll(imageBooks.whereType<Book>());
      print('[BookService] image-books=${imageBooks.whereType<Book>().length}');
    } catch (e) {
      print('Error loading image books: $e');
    }

    try {
      final pdfBooks = await _pdfService.loadImportedPdfs().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('Timed out loading PDFs');
          return <Book>[];
        },
      );
      books.addAll(pdfBooks);
      print('[BookService] pdf-books=${pdfBooks.length}');
    } catch (e) {
      print('Error loading PDFs: $e');
    }

    try {
      final epubBooks = await _epubLibraryService.loadLibraryBooks().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          print('Timed out loading EPUB library');
          return <Book>[];
        },
      );
      books.addAll(epubBooks);
      print('[BookService] epub-books=${epubBooks.length}');
    } catch (e) {
      print('Error loading EPUB library: $e');
    }

    return books;
  }

  void _logBookCounts(String phase, List<Book> books) {
    final epubCount = books.where((book) => book.isEpub).length;
    final pdfCount = books.where((book) => book.isPdf).length;
    final imageCount = books.length - epubCount - pdfCount;
    print(
      '[BookService] $phase total=${books.length} images=$imageCount epubs=$epubCount pdfs=$pdfCount ids=${books.map((book) => book.id).join(',')}',
    );
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
