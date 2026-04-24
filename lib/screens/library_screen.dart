import 'package:flutter/material.dart';
import 'dart:io';
import '../models/book.dart';
import '../services/book_service.dart';
import '../services/epub_library_service.dart';
import '../services/reading_stats_service.dart';
import '../screens/reader_screen.dart';
import '../theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final BookService _bookService = BookService();
  final EpubLibraryService _epubLibraryService = EpubLibraryService();
  final ReadingStatsService _readingStatsService = ReadingStatsService();
  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  Map<String, BookStatus> _bookStatuses = {};
  bool _isLoading = true;
  bool _isImporting = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  LibraryFilter _activeFilter = LibraryFilter.all;
  LibrarySort _activeSort = LibrarySort.recent;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadBooks({bool forceRefresh = false}) async {
    final books = await _bookService.loadAllBooks(forceRefresh: forceRefresh);
    final statuses = await _readingStatsService.getAllBookStatuses();
    if (!mounted) {
      return;
    }
    setState(() {
      _books = books;
      _bookStatuses = statuses;
      _filteredBooks = _applyFiltersAndSort(books);
      _isLoading = false;
    });
  }

  void _filterBooks(String query) {
    setState(() {
      _filteredBooks = _applyFiltersAndSort(_books);
    });
  }

  List<Book> _applyFiltersAndSort(List<Book> books) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = books.where((book) {
      final titleMatch = query.isEmpty || book.title.toLowerCase().contains(query);
      final authorMatch =
          query.isEmpty || (book.author?.toLowerCase().contains(query) ?? false);
      final matchesQuery = query.isEmpty || titleMatch || authorMatch;
      if (!matchesQuery) {
        return false;
      }
      return _matchesActiveFilter(book);
    }).toList();

    filtered.sort(_compareBooks);
    return filtered;
  }

  bool _matchesActiveFilter(Book book) {
    final status = _bookStatuses[book.id];
    switch (_activeFilter) {
      case LibraryFilter.all:
        return true;
      case LibraryFilter.inProgress:
        return status?.category == BookCategory.currentlyReading;
      case LibraryFilter.finished:
        return status?.category == BookCategory.finished;
      case LibraryFilter.unread:
        return status == null ||
            status.category == BookCategory.wantToRead ||
            (status.category == BookCategory.currentlyReading &&
                status.currentPage == 0);
      case LibraryFilter.epub:
        return book.isEpub;
      case LibraryFilter.images:
        return !book.isEpub && !book.isPdf;
    }
  }

  int _compareBooks(Book left, Book right) {
    switch (_activeSort) {
      case LibrarySort.recent:
      case LibrarySort.lastOpened:
        final leftTime = _bookStatuses[left.id]?.lastReadAt ??
            left.lastReadAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final rightTime = _bookStatuses[right.id]?.lastReadAt ??
            right.lastReadAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return rightTime.compareTo(leftTime);
      case LibrarySort.titleAz:
        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
      case LibrarySort.authorAz:
        final authorCompare = (left.author ?? '').toLowerCase().compareTo(
          (right.author ?? '').toLowerCase(),
        );
        if (authorCompare != 0) {
          return authorCompare;
        }
        return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    }
  }

  Map<String, List<Book>> _buildAlphabetSections(List<Book> books) {
    final sections = <String, List<Book>>{};
    for (final book in books) {
      final trimmed = book.title.trim();
      final key = trimmed.isEmpty
          ? '#'
          : RegExp(r'^[A-Za-z]').hasMatch(trimmed[0])
              ? trimmed[0].toUpperCase()
              : '#';
      sections.putIfAbsent(key, () => []).add(book);
    }
    return Map.fromEntries(
      sections.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  void _openBook(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReaderScreen(book: book)),
    ).then((_) => _loadBooks());
  }

  Future<void> _importBook() async {
    if (_isImporting) {
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final importedBook = await _epubLibraryService.importFromFilesystem();
      if (!mounted) {
        return;
      }

      if (importedBook != null) {
        _bookService.invalidateCache();
        await _loadBooks(forceRefresh: true);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported "${importedBook.title}"')));
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import EPUB: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _deleteBook(Book book) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: const Text('Remove Book', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${book.title}" from this device?',
          style: TextStyle(color: Colors.white.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) {
      return;
    }

    await _epubLibraryService.deleteBook(book);
    _bookService.invalidateCache();
    await _loadBooks(forceRefresh: true);

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Removed "${book.title}"')));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside search bar
          FocusScope.of(context).unfocus();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearchBar(),
            _buildToolbar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  : _filteredBooks.isEmpty
                  ? _buildEmptyState()
                  : _LibraryCollectionView(
                      books: _filteredBooks,
                      groupedBooks: _activeSort == LibrarySort.titleAz
                          ? _buildAlphabetSections(_filteredBooks)
                          : null,
                      statuses: _bookStatuses,
                      onBookTap: _openBook,
                      onDelete: _deleteBook,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF172033).withOpacity(0.78),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _filterBooks,
          autofocus: false,
          style: const TextStyle(color: Colors.white),
          textInputAction: TextInputAction.search,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: 'Search by title or author...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.72)),
            prefixIcon: Icon(
              Icons.search,
              color: AppTheme.primaryOrange,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: Colors.white.withOpacity(0.75),
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _filterBooks('');
                      _searchFocusNode.requestFocus();
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sortControl = Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<LibrarySort>(
                value: _activeSort,
                dropdownColor: const Color(0xFF1A1F2E),
                iconEnabledColor: Colors.white.withOpacity(0.8),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _activeSort = value;
                    _filteredBooks = _applyFiltersAndSort(_books);
                  });
                },
                items: const [
                  DropdownMenuItem(
                    value: LibrarySort.recent,
                    child: Text('Recent'),
                  ),
                  DropdownMenuItem(
                    value: LibrarySort.lastOpened,
                    child: Text('Last Opened'),
                  ),
                  DropdownMenuItem(
                    value: LibrarySort.titleAz,
                    child: Text('Title A-Z'),
                  ),
                  DropdownMenuItem(
                    value: LibrarySort.authorAz,
                    child: Text('Author'),
                  ),
                ],
              ),
            ),
          );

          final filterChips = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LibraryFilter.values
                .map(
                  (filter) => ChoiceChip(
                    label: Text(_filterLabel(filter)),
                    selected: _activeFilter == filter,
                    onSelected: (_) {
                      setState(() {
                        _activeFilter = filter;
                        _filteredBooks = _applyFiltersAndSort(_books);
                      });
                    },
                    labelStyle: TextStyle(
                      color: _activeFilter == filter
                          ? Colors.white
                          : Colors.white.withOpacity(0.78),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    backgroundColor: Colors.white.withOpacity(0.08),
                    selectedColor: AppTheme.primaryOrange.withOpacity(0.84),
                    side: BorderSide(
                      color: _activeFilter == filter
                          ? Colors.transparent
                          : Colors.white.withOpacity(0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                )
                .toList(),
          );

          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                filterChips,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: sortControl),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: filterChips),
              const SizedBox(width: 12),
              sortControl,
            ],
          );
        },
      ),
    );
  }

  String _filterLabel(LibraryFilter filter) {
    switch (filter) {
      case LibraryFilter.all:
        return 'All';
      case LibraryFilter.inProgress:
        return 'In Progress';
      case LibraryFilter.finished:
        return 'Finished';
      case LibraryFilter.unread:
        return 'Unread';
      case LibraryFilter.epub:
        return 'EPUB';
      case LibraryFilter.images:
        return 'Images';
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.accentIndigo, AppTheme.accentPurple],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentIndigo.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.collections_bookmark,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Library',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isLoading
                      ? 'Loading your books...'
                      : '${_books.length} ${_books.length == 1 ? 'book' : 'books'} available',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _isImporting ? null : _importBook,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentIndigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _isImporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: Text(_isImporting ? 'Importing...' : 'Import EPUB'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        margin: const EdgeInsets.all(24),
        decoration: AppTheme.glassDecoration(radius: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 64,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 20),
            Text(
              'Your library is empty',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Import an EPUB to start your library',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum LibraryFilter { all, inProgress, finished, unread, epub, images }

enum LibrarySort { recent, lastOpened, titleAz, authorAz }

class _LibraryCollectionView extends StatelessWidget {
  final List<Book> books;
  final Map<String, List<Book>>? groupedBooks;
  final Map<String, BookStatus> statuses;
  final Function(Book) onBookTap;
  final Function(Book) onDelete;

  const _LibraryCollectionView({
    required this.books,
    required this.groupedBooks,
    required this.statuses,
    required this.onBookTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (groupedBooks != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: groupedBooks!.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _ResponsiveBookGrid(
                  books: entry.value,
                  statuses: statuses,
                  onBookTap: onBookTap,
                  onDelete: onDelete,
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        _ResponsiveBookGrid(
          books: books,
          statuses: statuses,
          onBookTap: onBookTap,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

class _ResponsiveBookGrid extends StatelessWidget {
  final List<Book> books;
  final Map<String, BookStatus> statuses;
  final Function(Book) onBookTap;
  final Function(Book) onDelete;

  const _ResponsiveBookGrid({
    required this.books,
    required this.statuses,
    required this.onBookTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth >= 1100) {
          crossAxisCount = 5;
        } else if (constraints.maxWidth >= 820) {
          crossAxisCount = 4;
        } else if (constraints.maxWidth >= 560) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.92,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
          ),
          itemCount: books.length,
          itemBuilder: (context, index) {
            final book = books[index];
            return _ModernBookCard(
              book: book,
              status: statuses[book.id],
              onTap: () => onBookTap(book),
              onDelete: book.canDelete ? () => onDelete(book) : null,
            );
          },
        );
      },
    );
  }
}

class _ModernBookCard extends StatelessWidget {
  final Book book;
  final BookStatus? status;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _ModernBookCard({
    required this.book,
    required this.status,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const coverHeight = 108.0;
    final statusLabel = _statusLabel(status);
    final statusColor = _statusColor(status);
    final lastOpened = status?.lastReadAt;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF7F1E3), Color(0xFFE8DEC8)],
          ),
          border: Border.all(color: const Color(0xFFD4C3A3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: coverHeight,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                        child: SizedBox.expand(
                          child: _BookCoverArt(book: book),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 1,
                          color: const Color(0xFFD9CEB3),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF31435F).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            book.isEpub ? 'EPUB' : 'Images',
                            style: const TextStyle(
                              color: Color(0xFF51627C),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF31435F).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${book.totalPages}',
                            style: const TextStyle(
                              color: Color(0xFF31435F),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFFCFAF4),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: const TextStyle(
                            color: Color(0xFF1F2937),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            height: 1.15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          book.author ?? 'Unknown Author',
                          style: const TextStyle(
                            color: Color(0xFF51627C),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MetaChip(
                              label: book.isEpub
                                  ? 'EPUB'
                                  : (book.isPdf ? 'PDF' : 'Images'),
                              color: const Color(0xFF51627C),
                            ),
                            if (statusLabel != null)
                              _MetaChip(
                                label: statusLabel,
                                color: statusColor,
                              ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          lastOpened == null
                              ? 'Not opened yet'
                              : 'Last opened ${_relativeLabel(lastOpened)}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (onDelete != null)
              Positioned(
                top: 10,
                right: 10,
                child: PopupMenuButton<String>(
                  tooltip: 'Book options',
                  onSelected: (value) {
                    if (value == 'delete') {
                      onDelete?.call();
                    }
                  },
                  color: const Color(0xFF1A1F2E),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Remove from device'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _statusLabel(BookStatus? status) {
    if (status == null) return null;
    switch (status.category) {
      case BookCategory.wantToRead:
        return 'Unread';
      case BookCategory.currentlyReading:
        return 'In Progress';
      case BookCategory.finished:
        return 'Finished';
    }
  }

  Color _statusColor(BookStatus? status) {
    if (status == null) return const Color(0xFF51627C);
    switch (status.category) {
      case BookCategory.wantToRead:
        return const Color(0xFF51627C);
      case BookCategory.currentlyReading:
        return AppTheme.accentTeal;
      case BookCategory.finished:
        return AppTheme.accentGreen;
    }
  }

  String _relativeLabel(DateTime value) {
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    }
    if (difference.inDays == 1) {
      return 'yesterday';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }
    return '${value.month}/${value.day}/${value.year}';
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BookCoverArt extends StatelessWidget {
  final Book book;

  const _BookCoverArt({required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book.coverPath;
    if (coverPath != null && coverPath.isNotEmpty) {
      final coverFile = File(coverPath);
      if (coverFile.existsSync()) {
        return Image.file(
          coverFile,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _fallbackCover();
          },
        );
      }
    }

    return _fallbackCover();
  }

  Widget _fallbackCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F1E3), Color(0xFFE8DEC8)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            width: 18,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF31435F).withOpacity(0.95),
                    const Color(0xFF1A2436).withOpacity(0.95),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.menu_book_rounded,
              size: 60,
              color: const Color(0xFF31435F).withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}
