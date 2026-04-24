import 'dart:math' as math;
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/book_service.dart';
import '../services/reading_stats_service.dart';
import '../models/book.dart';
import '../screens/reader_screen.dart';
import '../theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final BookService _bookService = BookService();
  final ReadingStatsService _statsService = ReadingStatsService();
  List<Book> _allBooks = [];
  List<Book> _continueReadingBooks = [];
  List<Book> _quickFindBooks = [];
  bool _isLoading = true;
  bool _showStatsWidget = true;
  ReadingStats? _readingStats;
  Map<BookCategory, int> _categoryCounts = {};
  Map<String, BookStatus> _bookStatuses = {};
  final TextEditingController _continueSearchController =
      TextEditingController();
  final TextEditingController _librarySearchController =
      TextEditingController();
  final FocusNode _continueSearchFocusNode = FocusNode();
  final FocusNode _librarySearchFocusNode = FocusNode();
  final ScrollController _quickFindScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadBooks();
    _loadStats();
  }

  Future<void> _loadStats() async {
    _showStatsWidget = await _statsService.getShowStatsWidget();
    _readingStats = await _statsService.getReadingStats();
    _categoryCounts = await _statsService.getCategoryCounts();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _continueSearchController.dispose();
    _librarySearchController.dispose();
    _continueSearchFocusNode.dispose();
    _librarySearchFocusNode.dispose();
    _quickFindScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBooks() async {
    final books = await _bookService.loadAllBooks();
    final statuses = await _statsService.getAllBookStatuses();
    if (!mounted) return;
    setState(() {
      _allBooks = books;
      _bookStatuses = statuses;
      _applyHomeFilters(statuses);
      _isLoading = false;
    });
  }

  void _applyHomeFilters(Map<String, BookStatus> statuses) {
    final continueReading = _buildContinueReadingBooks(_allBooks, statuses);

    _continueReadingBooks = _filterBooks(
      continueReading,
      _continueSearchController.text,
    );
    _quickFindBooks = _buildQuickFindBooks(
      _filterBooks(_allBooks, _librarySearchController.text),
      statuses,
    );
  }

  List<Book> _buildContinueReadingBooks(
    List<Book> books,
    Map<String, BookStatus> statuses,
  ) {
    final active = <({Book book, BookStatus status})>[];

    for (final book in books) {
      final status = statuses[book.id];
      if (status == null || status.category != BookCategory.currentlyReading) {
        continue;
      }
      if (status.totalPages <= 0) {
        continue;
      }
      if (status.progressPercent < 2 || status.progressPercent >= 95) {
        continue;
      }

      active.add((book: book, status: status));
    }

    active.sort((left, right) {
      final leftTime =
          left.status.lastReadAt ??
          left.status.startedReading ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          right.status.lastReadAt ??
          right.status.startedReading ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });

    return active.map((entry) => entry.book).toList();
  }

  List<Book> _buildQuickFindBooks(
    List<Book> books,
    Map<String, BookStatus> statuses,
  ) {
    final candidates = books.toList();

    candidates.sort((left, right) {
      final leftStatus = statuses[left.id];
      final rightStatus = statuses[right.id];
      final leftTime =
          leftStatus?.lastReadAt ??
          leftStatus?.startedReading ??
          left.lastReadAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final rightTime =
          rightStatus?.lastReadAt ??
          rightStatus?.startedReading ??
          right.lastReadAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return rightTime.compareTo(leftTime);
    });

    return candidates.take(8).toList();
  }

  List<Book> _filterBooks(List<Book> books, String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return books;
    }

    return books.where((book) {
      final titleMatch = book.title.toLowerCase().contains(trimmed);
      final authorMatch = book.author?.toLowerCase().contains(trimmed) ?? false;
      return titleMatch || authorMatch;
    }).toList();
  }

  void _updateSectionFilters() {
    setState(() {
      _applyHomeFilters(_bookStatuses);
    });
  }

  Future<void> _refreshHomeData() async {
    await _loadStats();
    await _loadBooks();
  }

  void _openBook(Book book) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ReaderScreen(book: book)),
    ).then((_) => _refreshHomeData());
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside search bar
          FocusScope.of(context).unfocus();
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(0, constraints.maxHeight - 32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    if (_showStatsWidget && !_isLoading) ...[
                      _buildStatsWidget(),
                      const SizedBox(height: 24),
                    ],
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    else if (_allBooks.isEmpty)
                      _buildEmptyState()
                    else
                      _buildLibraryAndReadingLayout(constraints.maxWidth),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatsWidget() {
    final readingNow = _categoryCounts[BookCategory.currentlyReading] ?? 0;
    final finishedThisMonth = _readingStats?.booksReadMTD ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF243559).withOpacity(0.72),
            const Color(0xFF16243D).withOpacity(0.68),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.menu_book, color: AppTheme.primaryOrange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Reading Stats',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.96),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildPrimaryStat(
                  'Reading Now',
                  readingNow,
                  Icons.auto_stories,
                  AppTheme.accentTeal,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPrimaryStat(
                  'Finished This Month',
                  finishedThisMonth,
                  Icons.check_circle,
                  AppTheme.accentGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _buildStatsStatusLine(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.82),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryStat(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 10,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _buildStatsStatusLine() {
    final readingNow = _categoryCounts[BookCategory.currentlyReading] ?? 0;
    final lastFinishedTitle = _findLastFinishedTitle();
    final finishedThisMonth = _readingStats?.booksReadMTD ?? 0;

    if (readingNow > 0 && lastFinishedTitle != null) {
      return '$readingNow books in progress  •  Last finished: $lastFinishedTitle';
    }

    if (finishedThisMonth > 0) {
      return '$finishedThisMonth books finished this month';
    }

    if (readingNow > 0) {
      return '$readingNow books in progress • Continue reading picks up from your last opened book';
    }

    return 'Start a book to build your reading streak.';
  }

  String? _findLastFinishedTitle() {
    final finishedStatuses = _bookStatuses.values.where(
      (status) =>
          status.category == BookCategory.finished &&
          status.finishedReading != null,
    );

    if (finishedStatuses.isEmpty) {
      return null;
    }

    final latest = finishedStatuses.reduce((current, next) {
      final currentFinished = current.finishedReading!;
      final nextFinished = next.finishedReading!;
      return nextFinished.isAfter(currentFinished) ? next : current;
    });

    for (final book in _allBooks) {
      if (book.id == latest.bookId) {
        return book.title;
      }
    }

    return null;
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryOrange, AppTheme.secondaryOrange],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryOrange.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: -5,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.auto_stories,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storytime!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Time for a new adventure',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
    required String hintText,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchBox = SizedBox(
          width: constraints.maxWidth > 720 ? 240 : double.infinity,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF172033).withOpacity(0.78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppTheme.primaryOrange,
                  size: 18,
                ),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Colors.white.withOpacity(0.75),
                          size: 18,
                        ),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      )
                    : null,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
        );

        final titleBlock = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryOrange, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        if (constraints.maxWidth <= 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 12),
              searchBox,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 16),
            searchBox,
          ],
        );
      },
    );
  }

  Widget _buildLibraryAndReadingLayout(double maxWidth) {
    if (maxWidth < 980) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildContinueReadingPanel(),
          const SizedBox(height: 24),
          SizedBox(
            height: 360,
            child: _buildQuickFindPanel(),
          ),
        ],
      );
    }

    return SizedBox(
      height: 360,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: _buildContinueReadingPanel(),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 5,
            child: _buildQuickFindPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueReadingPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.glassDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.play_circle_filled,
            title: 'Continue Reading',
            subtitle: _continueReadingBooks.isEmpty
                ? 'Pick up where you left off'
                : '${_continueReadingBooks.length} books in progress',
            controller: _continueSearchController,
            focusNode: _continueSearchFocusNode,
            onChanged: (_) => _updateSectionFilters(),
            hintText: 'Search books in progress',
          ),
          const SizedBox(height: 16),
          if (_continueReadingBooks.isEmpty)
            _buildSectionEmptyState(
              'No books in progress yet',
              'Start a story and it will appear here.',
            )
          else
            _BookCarousel(
              books: _continueReadingBooks,
              onBookTap: _openBook,
              cardType: CardType.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildQuickFindPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.glassDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            icon: Icons.library_books,
            title: 'Quick Find Library',
            subtitle: 'Search your full shelf and jump right in',
            controller: _librarySearchController,
            focusNode: _librarySearchFocusNode,
            onChanged: (_) => _updateSectionFilters(),
            hintText: 'Search all library books',
          ),
          const SizedBox(height: 14),
          if (_quickFindBooks.isEmpty)
            _buildSectionEmptyState(
              'No matching books found',
              'Try a different title or author search.',
            )
          else
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Scrollbar(
                  controller: _quickFindScrollController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: _quickFindScrollController,
                    padding: const EdgeInsets.all(10),
                    itemCount: _quickFindBooks.length,
                    itemBuilder: (context, index) {
                      final book = _quickFindBooks[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _QuickFindBookRow(
                          book: book,
                          status: _bookStatuses[book.id],
                          onTap: () => _openBook(book),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionEmptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.glassDecoration(radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: AppTheme.glassDecoration(radius: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No books yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Go to Discover to find new stories',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

enum CardType { compact, featured }

class _BookCarousel extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;
  final CardType cardType;

  const _BookCarousel({
    required this.books,
    required this.onBookTap,
    required this.cardType,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final visibleItems = constraints.maxWidth > 700 ? 2.15 : 1.45;
        final calculatedWidth =
            (constraints.maxWidth - (16 * (visibleItems.ceil() - 1))) /
            visibleItems;
        final itemWidth = cardType == CardType.compact
            ? math.min(calculatedWidth, 180.0)
            : calculatedWidth;

        return SizedBox(
          height: cardType == CardType.featured ? 220 : 182,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: books.length,
            padding: const EdgeInsets.only(right: 24),
            itemBuilder: (context, index) {
              final book = books[index];
              return _ModernBookCard(
                book: book,
                onTap: () => onBookTap(book),
                cardType: cardType,
                width: itemWidth,
              );
            },
          ),
        );
      },
    );
  }
}

class _ModernBookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final CardType cardType;
  final double width;

  const _ModernBookCard({
    required this.book,
    required this.onTap,
    required this.cardType,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final coverHeight = cardType == CardType.featured ? 124.0 : 94.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        margin: const EdgeInsets.only(right: 16),
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
              blurRadius: 16,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
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
                  if (cardType == CardType.featured)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF31435F).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${book.totalPages}',
                          style: const TextStyle(
                            color: Color(0xFF31435F),
                            fontSize: 11,
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
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                      maxLines: cardType == CardType.featured ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (cardType == CardType.featured) ...[
                      const SizedBox(height: 3),
                      Text(
                        book.author ?? 'Unknown Author',
                        style: const TextStyle(
                          color: Color(0xFF51627C),
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickFindBookRow extends StatelessWidget {
  final Book book;
  final BookStatus? status;
  final VoidCallback onTap;

  const _QuickFindBookRow({
    required this.book,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = status?.category;
    final progress = status?.progressPercent ?? 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 68,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _BookCoverArt(book: book),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author ?? 'Unknown Author',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _QuickFindChip(
                        label: book.isEpub ? 'EPUB' : 'Images',
                        color: AppTheme.primaryOrange,
                      ),
                      if (category != null)
                        _QuickFindChip(
                          label: _categoryLabel(category),
                          color: category == BookCategory.finished
                              ? AppTheme.accentGreen
                              : AppTheme.accentTeal,
                        ),
                      if (progress > 0 && category != BookCategory.finished)
                        _QuickFindChip(
                          label: '${progress.round()}%',
                          color: AppTheme.accentBlue,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.white.withOpacity(0.55),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(BookCategory category) {
    switch (category) {
      case BookCategory.wantToRead:
        return 'Want to read';
      case BookCategory.currentlyReading:
        return 'Reading';
      case BookCategory.finished:
        return 'Finished';
    }
  }
}

class _QuickFindChip extends StatelessWidget {
  final String label;
  final Color color;

  const _QuickFindChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
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
              size: 56,
              color: const Color(0xFF31435F).withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }
}
