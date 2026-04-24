import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import '../models/book.dart';

class PdfService {
  static const String _importedPath = 'assets/imported';
  static const List<String> _knownPdfs = [
    // Add PDF filenames here as needed
    // e.g., 'my_book.pdf'
  ];

  Future<List<Book>> loadImportedPdfs() async {
    final books = <Book>[];

    for (final pdfName in _knownPdfs) {
      try {
        final assetPath = '$_importedPath/$pdfName';
        final book = await loadPdf(assetPath);
        if (book != null) {
          books.add(book);
        }
      } catch (e) {
        print('Error loading PDF $pdfName: $e');
      }
    }

    return books;
  }

  Future<Book?> loadPdf(String assetPath) async {
    try {
      // For PDFs, we'll create a book with a single page that holds the PDF path
      // The actual rendering will be done by the PDF viewer widget
      final bookId = path.basename(assetPath).replaceAll('.pdf', '');

      // Try to load to verify it exists
      await rootBundle.load(assetPath);

      return Book(
        id: bookId,
        title: bookId.replaceAll('_', ' ').replaceAll('-', ' '),
        author: 'PDF Document',
        pages: [PageAsset(pageNumber: 1, imagePath: assetPath)],
        isEpub: false,
        isPdf: true,
      );
    } catch (e) {
      print('Error loading PDF $assetPath: $e');
      return null;
    }
  }

  // Scan for PDF files in the imported folder
  Future<List<String>> scanForPdfs() async {
    // Since we can't dynamically list assets, return known PDFs
    return _knownPdfs;
  }

  // Add a PDF to the known list
  void addPdf(String filename) {
    if (!_knownPdfs.contains(filename)) {
      _knownPdfs.add(filename);
    }
  }
}
