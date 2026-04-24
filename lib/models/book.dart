/// Represents a chapter or section in a book
class Chapter {
  final String title;
  final String href; // Path or anchor within the EPUB
  final int? order; // Optional ordering index

  const Chapter({required this.title, required this.href, this.order});
}

/// Represents a single page (for image-based books)
class PageAsset {
  final int pageNumber;
  final String imagePath;
  final int? chapterIndex;
  final String? title;

  const PageAsset({
    required this.pageNumber,
    required this.imagePath,
    this.chapterIndex,
    this.title,
  });
}

/// Book model - supports both EPUB (via EPUB.js) and image-based books
class Book {
  final String id;
  final String title;
  final String? author;
  final String? coverPath; // Path to cover image
  final String? originalFilePath; // Raw EPUB file path in app storage
  final String? extractPath; // EPUB extract directory (for EPUB.js)
  final List<PageAsset> pages; // For image-based books
  final List<Chapter> chapters; // Table of contents
  final bool isEpub;
  final bool isPdf;
  final bool canDelete;
  final String? lastPositionCfi; // EPUB CFI for last reading position
  final DateTime? lastReadAt;

  const Book({
    required this.id,
    required this.title,
    this.author,
    this.coverPath,
    this.originalFilePath,
    this.extractPath,
    this.pages = const [],
    this.chapters = const [],
    this.isEpub = false,
    this.isPdf = false,
    this.canDelete = false,
    this.lastPositionCfi,
    this.lastReadAt,
  });

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? coverPath,
    String? originalFilePath,
    String? extractPath,
    List<PageAsset>? pages,
    List<Chapter>? chapters,
    bool? isEpub,
    bool? isPdf,
    bool? canDelete,
    String? lastPositionCfi,
    DateTime? lastReadAt,
  }) {
    return Book(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      originalFilePath: originalFilePath ?? this.originalFilePath,
      extractPath: extractPath ?? this.extractPath,
      pages: pages ?? this.pages,
      chapters: chapters ?? this.chapters,
      isEpub: isEpub ?? this.isEpub,
      isPdf: isPdf ?? this.isPdf,
      canDelete: canDelete ?? this.canDelete,
      lastPositionCfi: lastPositionCfi ?? this.lastPositionCfi,
      lastReadAt: lastReadAt ?? this.lastReadAt,
    );
  }

  /// Total pages (for image books) or approximate (for EPUBs)
  int get totalPages =>
      isEpub ? 1 : pages.length; // EPUB.js reports the real count later

  /// Get a specific page (for image-based books only)
  PageAsset? getPage(int index) {
    if (isEpub) return null; // EPUB.js handles this
    if (index < 0 || index >= pages.length) return null;
    return pages[index];
  }
}
