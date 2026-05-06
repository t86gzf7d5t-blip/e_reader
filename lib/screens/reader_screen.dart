import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/character.dart';
import '../models/reader_safe_region.dart';
import '../widgets/book_page_view.dart';
import '../widgets/single_character_scene_overlay.dart';
import '../services/character_service.dart';
import '../services/background_service.dart';
import '../services/reading_stats_service.dart';
import '../theme.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;

  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late PageController _pageController;
  int _currentPage = 0;
  PageViewMode _viewMode = PageViewMode.single;
  double _fontSize = 18.0;
  SharedPreferences? _prefs;
  final ReadingStatsService _statsService = ReadingStatsService();
  bool _isLoading = true;
  String? _savedCfi; // For EPUB position restoration
  String? _currentCfi;
  int? _restorePageHint;
  int? _restoreTotalPagesHint;
  final GlobalKey<EpubJsReaderState> _epubReaderKey =
      GlobalKey<EpubJsReaderState>();
  int? _actualTotalPages; // Actual page count from EPUB
  List<Chapter> _epubChapters = const [];
  final CharacterService _characterService = CharacterService();
  final BackgroundService _backgroundService = BackgroundService();
  bool _showCharacters = true;
  bool _autoPlayCharacterAnimations = true;
  List<CharacterManifest> _characters = const [];
  String _characterStyle = 'default';
  int _characterSceneTrigger = 0;
  List<ReaderSafeRegion> _safeRegions = const [];
  Timer? _characterSceneSettleTimer;
  List<ReaderSafeRegion>? _pendingSafeRegions;
  int? _pendingCharacterScenePage;
  int? _lastSettledCharacterScenePage;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _trackBookOpen();
    _loadCharacterOverlayState();
    _backgroundService.addListener(_handleBackgroundStyleChanged);
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final savedPage = _prefs?.getInt('${_getBookKey()}_page') ?? 0;
    final savedFontSize =
        _prefs?.getDouble('${_getBookKey()}_fontsize') ?? 18.0;
    final savedViewMode = _prefs?.getBool('${_getBookKey()}_spread') ?? false;
    final savedCfi = _prefs?.getString('${_getBookKey()}_cfi');
    final savedTotalPagesHint = _prefs?.getInt('${_getBookKey()}_page_count');

    // For EPUBs, store the saved CFI for position restoration
    if (widget.book.isEpub && savedCfi != null) {
      _savedCfi = savedCfi;
      _currentCfi = savedCfi;
      _restorePageHint = savedPage >= 0 ? savedPage : null;
      _restoreTotalPagesHint = savedTotalPagesHint;
      debugPrint('Restoring EPUB position: $savedCfi');
    }

    setState(() {
      _currentPage = widget.book.isEpub
          ? (savedPage < 0 ? 0 : savedPage)
          : savedPage.clamp(0, widget.book.totalPages - 1);
      _fontSize = savedFontSize;
      _viewMode = savedViewMode ? PageViewMode.spread : PageViewMode.single;
      _isLoading = false;
    });

    _pageController = PageController(initialPage: _getPageIndex(_currentPage));
  }

  Future<void> _trackBookOpen() async {
    await _statsService.init();
    final status = await _statsService.getBookStatus(widget.book.id);

    // Only set to "currently reading" if not already finished
    if (status == null || status.category != BookCategory.finished) {
      await _statsService.setBookCategory(
        widget.book.id,
        BookCategory.currentlyReading,
      );
    }

    if (_hasReliableProgressTotal) {
      await _statsService.updateBookProgress(
        widget.book.id,
        _currentPage,
        _displayedTotalPages,
      );
    }
  }

  Future<void> _loadCharacterOverlayState() async {
    final showCharacters = await _characterService.getShowCharacters();
    final autoPlayAnimations = await _characterService.getAutoPlayAnimations();
    await _backgroundService.init();
    final currentStyle = await _backgroundService.getCurrentAnimationStyle();
    final availableCharacters = await _characterService
        .loadAvailableCharactersForStyle(currentStyle);
    if (!mounted) {
      return;
    }

    setState(() {
      _showCharacters = showCharacters;
      _autoPlayCharacterAnimations = autoPlayAnimations;
      _characters = availableCharacters
          .where((character) => character.hasIdleFrames)
          .take(1)
          .toList(growable: false);
      _characterStyle = currentStyle;
    });
  }

  Future<void> _handleBackgroundStyleChanged() async {
    final currentStyle = await _backgroundService.getCurrentAnimationStyle();
    final availableCharacters = await _characterService
        .loadAvailableCharactersForStyle(currentStyle);
    if (!mounted) {
      return;
    }

    setState(() {
      _characterStyle = currentStyle;
      _characters = availableCharacters
          .where((character) => character.hasIdleFrames)
          .take(1)
          .toList(growable: false);
    });
  }

  void _onSafeRegionsChanged(List<ReaderSafeRegion> regions) {
    if (!mounted) {
      return;
    }

    if (!widget.book.isEpub) {
      setState(() {
        _safeRegions = regions;
      });
      return;
    }

    _pendingSafeRegions = regions;
    _scheduleCharacterSceneSettle();
  }

  String _getBookKey() {
    return 'book_${widget.book.id}';
  }

  Future<void> _persistKnownTotalPages() async {
    if (!widget.book.isEpub) {
      await _prefs?.setInt(
        '${_getBookKey()}_page_count',
        widget.book.totalPages,
      );
      return;
    }

    final actualTotalPages = _actualTotalPages;
    if (actualTotalPages != null && actualTotalPages > 0) {
      await _prefs?.setInt('${_getBookKey()}_page_count', actualTotalPages);
    }
  }

  int _getPageIndex(int logicalPage) {
    if (_viewMode == PageViewMode.spread &&
        !widget.book.isEpub &&
        !widget.book.isPdf) {
      return logicalPage ~/ 2;
    }
    return logicalPage;
  }

  @override
  void dispose() {
    _saveProgress();
    _characterSceneSettleTimer?.cancel();
    _pageController.dispose();
    _backgroundService.removeListener(_handleBackgroundStyleChanged);
    super.dispose();
  }

  void _scheduleCharacterSceneSettle() {
    _characterSceneSettleTimer?.cancel();
    _characterSceneSettleTimer = Timer(const Duration(milliseconds: 420), () {
      if (!mounted) {
        return;
      }

      final pendingRegions = _pendingSafeRegions;
      final pendingPage = _pendingCharacterScenePage;
      debugPrint(
        '=== READERSCREEN: character scene settled at page ${pendingPage ?? _currentPage} with ${pendingRegions?.length ?? _safeRegions.length} safe regions ===',
      );

      setState(() {
        if (pendingRegions != null) {
          _safeRegions = pendingRegions;
        }
        if (pendingPage != null &&
            pendingPage != _lastSettledCharacterScenePage) {
          _characterSceneTrigger++;
          _lastSettledCharacterScenePage = pendingPage;
        }
      });
    });
  }

  Future<void> _saveProgress() async {
    await _prefs?.setInt('${_getBookKey()}_page', _currentPage);
    await _prefs?.setDouble('${_getBookKey()}_fontsize', _fontSize);
    await _prefs?.setBool(
      '${_getBookKey()}_spread',
      _viewMode == PageViewMode.spread,
    );
    await _persistKnownTotalPages();

    if (_hasReliableProgressTotal) {
      await _statsService.updateBookProgress(
        widget.book.id,
        _currentPage,
        _displayedTotalPages,
      );
    }
  }

  Future<void> _markBookFinished() async {
    await _statsService.setBookCategory(widget.book.id, BookCategory.finished);
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Marked as finished'),
        backgroundColor: AppTheme.darkBlueMid,
      ),
    );
  }

  void _onPageChanged(int pageIndex) {
    debugPrint('=== READERSCREEN: _onPageChanged called ===');
    debugPrint('Received pageIndex: $pageIndex');
    debugPrint('Current _currentPage: $_currentPage');

    int logicalPage = pageIndex;

    if (_viewMode == PageViewMode.spread &&
        !widget.book.isEpub &&
        !widget.book.isPdf) {
      logicalPage = pageIndex * 2;
    }

    final totalPages = _displayedTotalPages;
    final clampedPage = logicalPage.clamp(0, totalPages - 1);
    debugPrint(
      'Setting _currentPage to: $clampedPage (clamped from $logicalPage, total: $totalPages)',
    );

    setState(() {
      _currentPage = clampedPage;
      _restorePageHint = null;
      _restoreTotalPagesHint = null;
      if (!widget.book.isEpub) {
        _characterSceneTrigger++;
      }
    });

    if (widget.book.isEpub) {
      _pendingCharacterScenePage = clampedPage;
      _scheduleCharacterSceneSettle();
    }

    _saveProgress();
  }

  void _onPositionChanged(String cfi) {
    if (cfi.isEmpty) {
      return;
    }

    _currentCfi = cfi;
    _savedCfi = cfi;

    // Save EPUB CFI position to preferences
    _prefs?.setString('${_getBookKey()}_cfi', cfi);
    _persistKnownTotalPages();
  }

  void _goToPage(int page) {
    final totalPages = _displayedTotalPages;
    final targetPage = page.clamp(0, totalPages - 1);

    if (widget.book.isEpub) {
      _epubReaderKey.currentState?.goToPage(targetPage + 1);
    } else {
      // For image books, use PageController
      final pageIndex = _getPageIndex(targetPage);
      _pageController.animateToPage(
        pageIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    if (!widget.book.isEpub) {
      setState(() {
        _currentPage = targetPage;
      });
      _saveProgress();
    }
  }

  void _nextPage() {
    final totalPages = _actualTotalPages ?? widget.book.totalPages;
    if (_currentPage < totalPages - 1) {
      if (widget.book.isEpub) {
        _epubReaderKey.currentState?.nextPage();
      } else {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        setState(() {
          _currentPage = _currentPage + 1;
        });
        _saveProgress();
      }
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      if (widget.book.isEpub) {
        _epubReaderKey.currentState?.prevPage();
      } else {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        setState(() {
          _currentPage = _currentPage - 1;
        });
        _saveProgress();
      }
    }
  }

  void _onTotalPagesChanged(int totalPages) {
    debugPrint('=== READERSCREEN: onTotalPagesChanged called ===');
    debugPrint('Received totalPages: $totalPages');
    debugPrint('Current _actualTotalPages: $_actualTotalPages');
    debugPrint('book.totalPages: ${widget.book.totalPages}');

    if (totalPages != _actualTotalPages) {
      debugPrint('Updating _actualTotalPages to: $totalPages');
      setState(() {
        _actualTotalPages = totalPages;
      });
      _persistKnownTotalPages();
      _saveProgress();
    } else {
      debugPrint('No change needed, values match');
    }
  }

  bool get _hasReliableProgressTotal {
    if (!widget.book.isEpub) {
      return widget.book.totalPages > 0;
    }

    return _actualTotalPages != null && _actualTotalPages! > 1;
  }

  int get _displayedTotalPages {
    return _actualTotalPages ?? widget.book.totalPages;
  }

  String get _pageDisplayText {
    if (!widget.book.isEpub) {
      final currentDisplay = _currentPage + 1;
      return '$currentDisplay / ${widget.book.totalPages}';
    }

    final effectiveTotalPages = _actualTotalPages ?? _restoreTotalPagesHint;
    if (effectiveTotalPages == null || effectiveTotalPages <= 0) {
      return '... / ...';
    }

    final currentDisplay = (_currentPage + 1).clamp(1, effectiveTotalPages);
    if (_viewMode == PageViewMode.spread) {
      final rightPage = (_currentPage + 2).clamp(1, effectiveTotalPages);
      if (rightPage > currentDisplay) {
        return '$currentDisplay-$rightPage / $effectiveTotalPages';
      }
    }

    return '$currentDisplay / $effectiveTotalPages';
  }

  List<Chapter> get _displayChapters {
    final sourceChapters = widget.book.isEpub && _epubChapters.isNotEmpty
        ? _epubChapters
        : widget.book.chapters;
    final normalizedBookTitle = widget.book.title.trim().toLowerCase();
    final normalizedAuthor = widget.book.author?.trim().toLowerCase();
    final seenTitles = <String>{};
    final filtered = <Chapter>[];

    for (final chapter in sourceChapters) {
      final normalizedTitle = chapter.title.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (normalizedTitle.isEmpty) {
        continue;
      }

      final loweredTitle = normalizedTitle.toLowerCase();
      if (loweredTitle == normalizedBookTitle) {
        continue;
      }
      if (normalizedAuthor != null && loweredTitle == normalizedAuthor) {
        continue;
      }
      if (loweredTitle == 'the end') {
        continue;
      }
      if (loweredTitle.contains('project gutenberg')) {
        continue;
      }
      if (loweredTitle.contains('license')) {
        continue;
      }
      if (loweredTitle.contains('copyright')) {
        continue;
      }
      if (!seenTitles.add(loweredTitle)) {
        continue;
      }

      filtered.add(
        Chapter(
          title: normalizedTitle,
          href: chapter.href,
          order: chapter.order,
        ),
      );
    }

    return filtered;
  }

  bool get _hasUsefulChapterNavigation {
    if (!widget.book.isEpub && widget.book.chapters.isEmpty) {
      return false;
    }

    return _displayChapters.length >= 2;
  }

  void _onTableOfContentsChanged(List<Chapter> chapters) {
    if (!mounted) {
      return;
    }

    final filteredIncoming = chapters
        .where(
          (chapter) =>
              chapter.title.trim().isNotEmpty && chapter.href.trim().isNotEmpty,
        )
        .toList(growable: false);

    if (_sameChapterList(_epubChapters, filteredIncoming)) {
      return;
    }

    debugPrint(
      'Updating EPUB chapters from WebView TOC: ${filteredIncoming.length}',
    );
    setState(() {
      _epubChapters = filteredIncoming;
    });
  }

  bool _sameChapterList(List<Chapter> left, List<Chapter> right) {
    if (identical(left, right)) {
      return true;
    }
    if (left.length != right.length) {
      return false;
    }

    for (var i = 0; i < left.length; i++) {
      if (left[i].title != right[i].title ||
          left[i].href != right[i].href ||
          left[i].order != right[i].order) {
        return false;
      }
    }

    return true;
  }

  void _toggleViewMode() {
    final newMode = _viewMode == PageViewMode.single
        ? PageViewMode.spread
        : PageViewMode.single;

    // Save current position
    final currentLogicalPage = _currentPage;

    setState(() {
      _viewMode = newMode;
      // Keep _actualTotalPages until new count is reported
    });

    // Reinitialize page controller with new mode
    _pageController.dispose();
    _pageController = PageController(
      initialPage: _getPageIndex(currentLogicalPage),
    );

    _saveProgress();
  }

  void _showFontSizeDialog() {
    double dialogFontSize = _fontSize;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBlueMid,
        title: const Text('Font Size', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.text_fields,
                      color: Colors.white.withOpacity(0.5),
                      size: dialogFontSize - 4,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${dialogFontSize.toInt()}pt',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.text_fields,
                      color: Colors.white.withOpacity(0.5),
                      size: dialogFontSize + 4,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Slider(
                  value: dialogFontSize,
                  min: 12.0,
                  max: 32.0,
                  divisions: 10,
                  activeColor: AppTheme.primaryOrange,
                  inactiveColor: Colors.white.withOpacity(0.2),
                  onChanged: (value) {
                    setDialogState(() {
                      dialogFontSize = value;
                    });
                  },
                  onChangeEnd: (value) {
                    if ((value - _fontSize).abs() < 0.01) {
                      return;
                    }

                    setState(() {
                      _fontSize = value;
                    });
                    _saveProgress();
                  },
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              if ((dialogFontSize - _fontSize).abs() >= 0.01) {
                setState(() {
                  _fontSize = dialogFontSize;
                });
                _saveProgress();
              }
              Navigator.pop(context);
            },
            child: const Text(
              'Done',
              style: TextStyle(color: AppTheme.primaryOrange),
            ),
          ),
        ],
      ),
    );
  }

  void _showGoToPageDialog() {
    // Don't allow go-to-page if we don't know the actual page count yet
    if (widget.book.isEpub && _actualTotalPages == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for the book to fully load...'),
          backgroundColor: AppTheme.darkBlueMid,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final totalPages = widget.book.isEpub
        ? _actualTotalPages!
        : widget.book.totalPages;
    int selectedPage = _currentPage + 1;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppTheme.darkBlueMid,
          title: const Text(
            'Go to Page',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Page $selectedPage of $totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: selectedPage.toDouble(),
                min: 1,
                max: totalPages.toDouble(),
                divisions: totalPages - 1,
                label: selectedPage.toString(),
                activeColor: AppTheme.primaryOrange,
                inactiveColor: Colors.white.withOpacity(0.3),
                onChanged: (value) {
                  setState(() {
                    selectedPage = value.round();
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
            ),
            TextButton(
              onPressed: () {
                _goToPage(selectedPage - 1);
                Navigator.pop(context);
              },
              child: const Text(
                'Go',
                style: TextStyle(color: AppTheme.primaryOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChapterDialog() {
    final chapters = _displayChapters;

    if (chapters.isEmpty) {
      // Fallback: show message about no chapters
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No chapters available'),
          backgroundColor: AppTheme.darkBlueLight,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBlueMid,
        title: const Text('Chapters', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: chapters.length,
            itemBuilder: (context, index) {
              final chapter = chapters[index];
              return ListTile(
                title: Text(
                  chapter.title,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _goToChapter(chapter);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: AppTheme.primaryOrange),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1C2333),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Container(
      color: const Color(0xFF1C2333),
      child: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BookPageView(
                      book: widget.book.isEpub && _savedCfi != null
                          ? widget.book.copyWith(lastPositionCfi: _savedCfi)
                          : widget.book,
                      currentPage: _currentPage,
                      pageController: _pageController,
                      viewMode: _viewMode,
                      fontSize: _fontSize,
                      onPageChanged: _onPageChanged,
                      onPositionChanged: _onPositionChanged,
                      onTableOfContentsChanged: widget.book.isEpub
                          ? _onTableOfContentsChanged
                          : null,
                      onSafeRegionsChanged: widget.book.isEpub
                          ? _onSafeRegionsChanged
                          : null,
                      onTotalPagesChanged: widget.book.isEpub
                          ? _onTotalPagesChanged
                          : null,
                      epubReaderKey: widget.book.isEpub ? _epubReaderKey : null,
                      restorePageHint: widget.book.isEpub
                          ? _restorePageHint
                          : null,
                      restoreTotalPagesHint: widget.book.isEpub
                          ? _restoreTotalPagesHint
                          : null,
                    ),
                  ),
                  if (_showCharacters && _characters.isNotEmpty)
                    Positioned.fill(
                      child: SingleCharacterSceneOverlay(
                        character: _characters.first,
                        autoPlay: _autoPlayCharacterAnimations,
                      ),
                    ),
                ],
              ),
            ),
            _buildPageIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          _saveProgress();
          Navigator.pop(context);
        },
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.book.title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.book.author != null)
            Text(
              widget.book.author!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
        ],
      ),
      centerTitle: true,
      actions: [
        // Font size button (for all formats)
        IconButton(
          icon: const Icon(Icons.text_fields, color: Colors.white),
          onPressed: _showFontSizeDialog,
          tooltip: 'Font size',
        ),
        if (_hasUsefulChapterNavigation)
          IconButton(
            icon: const Icon(Icons.format_list_bulleted, color: Colors.white),
            onPressed: _showChapterDialog,
            tooltip: 'Chapters',
          ),
        IconButton(
          icon: const Icon(Icons.check_circle_outline, color: Colors.white),
          onPressed: _markBookFinished,
          tooltip: 'Mark finished',
        ),
        // View mode toggle
        _ViewModeToggle(viewMode: _viewMode, onToggle: _toggleViewMode),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildPageIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Previous page
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white54),
            onPressed: _currentPage > 0 ? _prevPage : null,
          ),
          // Page number (clickable)
          GestureDetector(
            onTap: _showGoToPageDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _pageDisplayText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Next page
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white54),
            onPressed: _currentPage < _displayedTotalPages - 1
                ? _nextPage
                : null,
          ),
        ],
      ),
    );
  }

  void _goToChapter(Chapter chapter) {
    if (widget.book.isEpub) {
      _epubReaderKey.currentState?.goToHref(chapter.href);
      return;
    }

    _goToPage(chapter.order ?? 0);
  }
}

class _ViewModeToggle extends StatelessWidget {
  final PageViewMode viewMode;
  final VoidCallback onToggle;

  const _ViewModeToggle({required this.viewMode, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            icon: Icons.chrome_reader_mode,
            label: '1',
            isSelected: viewMode == PageViewMode.single,
            onTap: onToggle,
            isLeft: true,
          ),
          _ToggleButton(
            icon: Icons.menu_book,
            label: '2',
            isSelected: viewMode == PageViewMode.spread,
            onTap: onToggle,
            isLeft: false,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLeft;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isLeft,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [AppTheme.primaryOrange, AppTheme.secondaryOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? const Radius.circular(20) : Radius.zero,
            right: isLeft ? Radius.zero : const Radius.circular(20),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : Colors.white70,
            ),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
