import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum BookCategory { wantToRead, currentlyReading, finished }

class BookStatus {
  final String bookId;
  final BookCategory category;
  final DateTime? startedReading;
  final DateTime? finishedReading;
  final DateTime? lastReadAt;
  final int currentPage;
  final int totalPages;

  BookStatus({
    required this.bookId,
    this.category = BookCategory.wantToRead,
    this.startedReading,
    this.finishedReading,
    this.lastReadAt,
    this.currentPage = 0,
    required this.totalPages,
  });

  Map<String, dynamic> toJson() {
    return {
      'bookId': bookId,
      'category': category.index,
      'startedReading': startedReading?.toIso8601String(),
      'finishedReading': finishedReading?.toIso8601String(),
      'lastReadAt': lastReadAt?.toIso8601String(),
      'currentPage': currentPage,
      'totalPages': totalPages,
    };
  }

  factory BookStatus.fromJson(Map<String, dynamic> json) {
    return BookStatus(
      bookId: json['bookId'],
      category: BookCategory.values[json['category'] ?? 0],
      startedReading: json['startedReading'] != null
          ? DateTime.parse(json['startedReading'])
          : null,
      finishedReading: json['finishedReading'] != null
          ? DateTime.parse(json['finishedReading'])
          : null,
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.parse(json['lastReadAt'])
          : null,
      currentPage: json['currentPage'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
    );
  }

  double get progressPercent =>
      totalPages > 0 ? ((currentPage + 1) / totalPages) * 100 : 0;
  bool get isFinished => category == BookCategory.finished;
}

class ReadingStats {
  final int booksReadYTD;
  final int booksReadMTD;
  final int totalPagesReadYTD;
  final int totalPagesReadMTD;
  final DateTime lastReset;

  ReadingStats({
    this.booksReadYTD = 0,
    this.booksReadMTD = 0,
    this.totalPagesReadYTD = 0,
    this.totalPagesReadMTD = 0,
    DateTime? lastReset,
  }) : lastReset = lastReset ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'booksReadYTD': booksReadYTD,
      'booksReadMTD': booksReadMTD,
      'totalPagesReadYTD': totalPagesReadYTD,
      'totalPagesReadMTD': totalPagesReadMTD,
      'lastReset': lastReset.toIso8601String(),
    };
  }

  factory ReadingStats.fromJson(Map<String, dynamic> json) {
    return ReadingStats(
      booksReadYTD: json['booksReadYTD'] ?? 0,
      booksReadMTD: json['booksReadMTD'] ?? 0,
      totalPagesReadYTD: json['totalPagesReadYTD'] ?? 0,
      totalPagesReadMTD: json['totalPagesReadMTD'] ?? 0,
      lastReset: json['lastReset'] != null
          ? DateTime.parse(json['lastReset'])
          : DateTime.now(),
    );
  }
}

class ReadingStatsService {
  static const String _bookStatusKey = 'book_statuses';
  static const String _readingStatsKey = 'reading_stats';
  static const String _showStatsWidgetKey = 'show_stats_widget';
  static const double _autoFinishThresholdPercent = 90.0;
  static const double _reopenFinishedThresholdPercent = 80.0;

  static final ReadingStatsService _instance = ReadingStatsService._internal();
  factory ReadingStatsService() => _instance;
  ReadingStatsService._internal();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Book Status Management
  Future<void> setBookCategory(String bookId, BookCategory category) async {
    await init();
    final statuses = await getAllBookStatuses();
    final existing = statuses[bookId];
    final wasFinished = existing?.category == BookCategory.finished;

    BookStatus newStatus;
    if (existing != null) {
      newStatus = BookStatus(
        bookId: bookId,
        category: category,
        startedReading:
            category == BookCategory.currentlyReading &&
                existing.startedReading == null
            ? DateTime.now()
            : existing.startedReading,
        finishedReading:
            category == BookCategory.finished &&
                existing.finishedReading == null
            ? DateTime.now()
            : existing.finishedReading,
        lastReadAt: category == BookCategory.wantToRead
            ? existing.lastReadAt
            : DateTime.now(),
        currentPage: existing.currentPage,
        totalPages: existing.totalPages,
      );
    } else {
      newStatus = BookStatus(
        bookId: bookId,
        category: category,
        startedReading: category == BookCategory.currentlyReading
            ? DateTime.now()
            : null,
        finishedReading: category == BookCategory.finished
            ? DateTime.now()
            : null,
        lastReadAt: category == BookCategory.wantToRead ? null : DateTime.now(),
        currentPage: 0,
        totalPages: 0,
      );
    }

    statuses[bookId] = newStatus;
    await _saveBookStatuses(statuses);

    // Update stats if book was finished
    if (category == BookCategory.finished && !wasFinished) {
      await _updateStatsOnFinish(newStatus);
    }
  }

  Future<void> updateBookProgress(
    String bookId,
    int currentPage,
    int totalPages,
  ) async {
    await init();
    final statuses = await getAllBookStatuses();
    final now = DateTime.now();
    final existing =
        statuses[bookId] ?? BookStatus(bookId: bookId, totalPages: totalPages);

    var nextCategory = existing.category;
    var nextStartedReading = existing.startedReading;
    var nextFinishedReading = existing.finishedReading;

    final progressPercent = totalPages > 0
        ? ((currentPage + 1) / totalPages) * 100
        : 0.0;
    final hasMeaningfulProgress = currentPage > 0 || progressPercent >= 2.0;
    final shouldReopenFinished =
        existing.category == BookCategory.finished &&
        totalPages > 0 &&
        progressPercent < _reopenFinishedThresholdPercent;

    if (shouldReopenFinished) {
      nextCategory = BookCategory.currentlyReading;
      nextFinishedReading = null;
      nextStartedReading ??= now;
    }

    if (nextCategory != BookCategory.finished && hasMeaningfulProgress) {
      nextCategory = BookCategory.currentlyReading;
      nextStartedReading ??= now;
    }

    final shouldAutoFinish =
        totalPages > 0 && progressPercent >= _autoFinishThresholdPercent;
    if (shouldAutoFinish && nextCategory != BookCategory.finished) {
      nextCategory = BookCategory.finished;
      nextFinishedReading ??= now;
    }

    final updated = BookStatus(
      bookId: bookId,
      category: nextCategory,
      startedReading: nextStartedReading,
      finishedReading: nextFinishedReading,
      lastReadAt: now,
      currentPage: currentPage,
      totalPages: totalPages,
    );

    statuses[bookId] = updated;
    await _saveBookStatuses(statuses);

    if (shouldReopenFinished && existing.finishedReading != null) {
      await _updateStatsOnUnfinish(existing);
    }

    if (nextCategory == BookCategory.finished &&
        existing.category != BookCategory.finished) {
      await _updateStatsOnFinish(updated);
    }
  }

  Future<BookStatus?> getBookStatus(String bookId) async {
    await init();
    final statuses = await getAllBookStatuses();
    return statuses[bookId];
  }

  Future<Map<String, BookStatus>> getAllBookStatuses() async {
    await init();
    final jsonStr = _prefs?.getString(_bookStatusKey);
    if (jsonStr == null) return {};

    final Map<String, dynamic> jsonMap = json.decode(jsonStr);
    return jsonMap.map(
      (key, value) => MapEntry(key, BookStatus.fromJson(value)),
    );
  }

  Future<void> repairPlaceholderEpubStatuses(
    Iterable<String> epubBookIds,
  ) async {
    await init();
    final epubIds = epubBookIds.toSet();
    if (epubIds.isEmpty) {
      return;
    }

    final statuses = await getAllBookStatuses();
    var changed = false;

    for (final bookId in epubIds) {
      final status = statuses[bookId];
      if (status == null ||
          status.category != BookCategory.finished ||
          status.totalPages > 1) {
        continue;
      }

      await _updateStatsOnUnfinish(status);
      statuses[bookId] = BookStatus(
        bookId: status.bookId,
        category: BookCategory.currentlyReading,
        startedReading:
            status.startedReading ?? status.lastReadAt ?? DateTime.now(),
        lastReadAt: status.lastReadAt,
        currentPage: status.currentPage,
        totalPages: 0,
      );
      changed = true;
    }

    if (changed) {
      await _saveBookStatuses(statuses);
    }
  }

  Future<void> _saveBookStatuses(Map<String, BookStatus> statuses) async {
    final jsonMap = statuses.map((key, value) => MapEntry(key, value.toJson()));
    await _prefs?.setString(_bookStatusKey, json.encode(jsonMap));
  }

  // Stats Management
  Future<ReadingStats> getReadingStats() async {
    await init();
    final jsonStr = _prefs?.getString(_readingStatsKey);
    if (jsonStr == null) return ReadingStats();

    return ReadingStats.fromJson(json.decode(jsonStr));
  }

  Future<void> _updateStatsOnFinish(BookStatus status) async {
    var stats = await getReadingStats();
    final now = DateTime.now();

    // Check if we need to reset MTD stats
    if (now.month != stats.lastReset.month ||
        now.year != stats.lastReset.year) {
      stats = ReadingStats(
        booksReadYTD: stats.booksReadYTD,
        booksReadMTD: 0,
        totalPagesReadYTD: stats.totalPagesReadYTD,
        totalPagesReadMTD: 0,
        lastReset: now,
      );
    }

    if (now.year != stats.lastReset.year) {
      stats = ReadingStats(lastReset: now);
    }

    final updatedStats = ReadingStats(
      booksReadYTD: stats.booksReadYTD + 1,
      booksReadMTD: stats.booksReadMTD + 1,
      totalPagesReadYTD: stats.totalPagesReadYTD + status.totalPages,
      totalPagesReadMTD: stats.totalPagesReadMTD + status.totalPages,
      lastReset: stats.lastReset,
    );

    await _saveReadingStats(updatedStats);
  }

  Future<void> _updateStatsOnUnfinish(BookStatus status) async {
    final finishedAt = status.finishedReading;
    if (finishedAt == null) {
      return;
    }

    var stats = await getReadingStats();
    final now = DateTime.now();

    final shouldAdjustYtd = finishedAt.year == now.year;
    final shouldAdjustMtd =
        finishedAt.year == now.year && finishedAt.month == now.month;

    if (!shouldAdjustYtd && !shouldAdjustMtd) {
      return;
    }

    stats = ReadingStats(
      booksReadYTD: shouldAdjustYtd
          ? (stats.booksReadYTD - 1).clamp(0, 1 << 30).toInt()
          : stats.booksReadYTD,
      booksReadMTD: shouldAdjustMtd
          ? (stats.booksReadMTD - 1).clamp(0, 1 << 30).toInt()
          : stats.booksReadMTD,
      totalPagesReadYTD: shouldAdjustYtd
          ? (stats.totalPagesReadYTD - status.totalPages)
                .clamp(0, 1 << 30)
                .toInt()
          : stats.totalPagesReadYTD,
      totalPagesReadMTD: shouldAdjustMtd
          ? (stats.totalPagesReadMTD - status.totalPages)
                .clamp(0, 1 << 30)
                .toInt()
          : stats.totalPagesReadMTD,
      lastReset: stats.lastReset,
    );

    await _saveReadingStats(stats);
  }

  Future<void> _saveReadingStats(ReadingStats stats) async {
    await _prefs?.setString(_readingStatsKey, json.encode(stats.toJson()));
  }

  Future<void> resetStats() async {
    await init();
    await _saveReadingStats(ReadingStats());
  }

  // Widget Visibility
  Future<bool> getShowStatsWidget() async {
    await init();
    return _prefs?.getBool(_showStatsWidgetKey) ?? true;
  }

  Future<void> setShowStatsWidget(bool show) async {
    await init();
    await _prefs?.setBool(_showStatsWidgetKey, show);
  }

  // Category counts
  Future<Map<BookCategory, int>> getCategoryCounts() async {
    final statuses = await getAllBookStatuses();
    final counts = <BookCategory, int>{
      BookCategory.wantToRead: 0,
      BookCategory.currentlyReading: 0,
      BookCategory.finished: 0,
    };

    for (final status in statuses.values) {
      counts[status.category] = (counts[status.category] ?? 0) + 1;
    }

    return counts;
  }

  Future<List<BookStatus>> getStatusesByCategory(BookCategory category) async {
    final statuses = await getAllBookStatuses();
    final filtered = statuses.values
        .where((status) => status.category == category)
        .toList();
    filtered.sort((a, b) {
      final left =
          a.lastReadAt ??
          a.startedReading ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          b.lastReadAt ??
          b.startedReading ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return filtered;
  }
}
