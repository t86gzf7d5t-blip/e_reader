import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/book.dart';
import '../models/reader_safe_region.dart';
import '../services/epub_service.dart';
import 'reader_swipe_physics.dart';

enum PageViewMode { single, spread }

/// Main book page view widget - routes to appropriate implementation
class BookPageView extends StatelessWidget {
  final Book book;
  final int currentPage;
  final PageController pageController;
  final PageViewMode viewMode;
  final double fontSize;
  final Function(int)? onPageChanged;
  final Function(String)? onPositionChanged; // CFI for EPUB
  final ValueChanged<List<Chapter>>? onTableOfContentsChanged;
  final ValueChanged<List<ReaderSafeRegion>>? onSafeRegionsChanged;
  final Function(int totalPages)?
  onTotalPagesChanged; // For EPUB to report actual page count
  final Key? epubReaderKey; // Key for accessing EpubJsReaderState
  final int? restorePageHint; // Zero-based logical page hint for EPUB restore
  final int? restoreTotalPagesHint;

  const BookPageView({
    super.key,
    required this.book,
    required this.currentPage,
    required this.pageController,
    this.viewMode = PageViewMode.single,
    this.fontSize = 18.0,
    this.onPageChanged,
    this.onPositionChanged,
    this.onTableOfContentsChanged,
    this.onSafeRegionsChanged,
    this.onTotalPagesChanged,
    this.epubReaderKey,
    this.restorePageHint,
    this.restoreTotalPagesHint,
  });

  @override
  Widget build(BuildContext context) {
    if (book.isEpub) {
      // Use EPUB.js for EPUB files with local HTTP server
      return EpubJsReader(
        key: epubReaderKey,
        book: book,
        currentPage: currentPage,
        pageController: pageController,
        viewMode: viewMode,
        fontSize: fontSize,
        onPageChanged: onPageChanged,
        onPositionChanged: onPositionChanged,
        onTableOfContentsChanged: onTableOfContentsChanged,
        onSafeRegionsChanged: onSafeRegionsChanged,
        onTotalPagesChanged: onTotalPagesChanged,
        restorePageHint: restorePageHint,
        restoreTotalPagesHint: restoreTotalPagesHint,
      );
    } else {
      // Use image-based reader for picture books
      return _ImageBookView(
        book: book,
        pageController: pageController,
        viewMode: viewMode,
        onPageChanged: onPageChanged,
      );
    }
  }
}

/// EPUB.js-based reader using WebView with local HTTP server
class EpubJsReader extends StatefulWidget {
  final Book book;
  final int currentPage;
  final PageController pageController;
  final PageViewMode viewMode;
  final double fontSize;
  final Function(int)? onPageChanged;
  final Function(String)? onPositionChanged; // CFI position
  final ValueChanged<List<Chapter>>? onTableOfContentsChanged;
  final ValueChanged<List<ReaderSafeRegion>>? onSafeRegionsChanged;
  final Function(int totalPages)?
  onTotalPagesChanged; // Report actual page count
  final int? restorePageHint; // Zero-based page hint
  final int? restoreTotalPagesHint;

  const EpubJsReader({
    super.key,
    required this.book,
    required this.currentPage,
    required this.pageController,
    required this.viewMode,
    required this.fontSize,
    this.onPageChanged,
    this.onPositionChanged,
    this.onTableOfContentsChanged,
    this.onSafeRegionsChanged,
    this.onTotalPagesChanged,
    this.restorePageHint,
    this.restoreTotalPagesHint,
  });

  @override
  State<EpubJsReader> createState() => EpubJsReaderState();
}

class EpubJsReaderState extends State<EpubJsReader> {
  final EpubService _epubService = EpubService();
  InAppWebViewController? _controller;
  bool _isReady = false;
  bool _bookNavReady = false; // Book ready for navigation
  bool _isDisposed = false;
  int _currentPage = 1;
  int _totalPages = 1;
  HttpServer? _localServer;
  String? _serverUrl;
  String? _pendingCfi; // CFI to restore when book is ready
  int? _pendingRestorePageHint;
  int? _pendingRestoreTotalPagesHint;

  @override
  void initState() {
    super.initState();
    _startLocalServer();
  }

  @override
  void didUpdateWidget(EpubJsReader oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update spread mode when view mode changes
    if (oldWidget.viewMode != widget.viewMode) {
      _updateSpreadMode();
    }

    // Update font size when it changes
    if (oldWidget.fontSize != widget.fontSize) {
      _updateFontSize();
    }
  }

  void _updateSpreadMode() {
    final spread = widget.viewMode == PageViewMode.spread;
    _evaluateJavascriptSafely('window.ReaderAPI.setSpread($spread)');
  }

  void _updateFontSize() {
    _evaluateJavascriptSafely(
      'window.ReaderAPI.setFontSize(${widget.fontSize})',
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller = null;
    _localServer?.close();
    super.dispose();
  }

  void _evaluateJavascriptSafely(String source) {
    if (_isDisposed) {
      return;
    }

    final controller = _controller;
    if (controller == null) {
      return;
    }

    try {
      controller.evaluateJavascript(source: source);
    } catch (e) {
      debugPrint('Ignoring WebView JS call after disposal: $e');
    }
  }

  Future<void> _startLocalServer() async {
    final preparedBook = await _epubService.ensureExtractedForReading(widget.book);
    if (_isDisposed || !mounted) {
      return;
    }

    final extractPath = preparedBook.extractPath;
    if (extractPath == null) return;

    try {
      // Create HTTP server on random available port
      _localServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _localServer!.port;
      _serverUrl = 'http://localhost:$port';

      debugPrint('Started local HTTP server at $_serverUrl');
      debugPrint('Serving EPUB from: $extractPath');

      // Handle requests
      _localServer!.listen((request) async {
        final path = request.uri.path;
        final filePath = '$extractPath$path';

        try {
          final file = File(filePath);
          if (await file.exists()) {
            final content = await file.readAsBytes();
            final contentType = _getContentType(filePath);

            request.response
              ..statusCode = 200
              ..headers.set('content-type', contentType)
              ..add(content);
          } else {
            request.response.statusCode = 404;
          }
        } catch (e) {
          debugPrint('Error serving $filePath: $e');
          request.response.statusCode = 500;
        }

        await request.response.close();
      });

      // Initialize WebView after server is ready
      _initWebView();
    } catch (e) {
      debugPrint('Error starting local server: $e');
    }
  }

  String _getContentType(String filePath) {
    final ext = filePath.toLowerCase();
    if (ext.endsWith('.html') ||
        ext.endsWith('.htm') ||
        ext.endsWith('.xhtml')) {
      return 'text/html';
    } else if (ext.endsWith('.css')) {
      return 'text/css';
    } else if (ext.endsWith('.js')) {
      return 'application/javascript';
    } else if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
      return 'image/jpeg';
    } else if (ext.endsWith('.png')) {
      return 'image/png';
    } else if (ext.endsWith('.gif')) {
      return 'image/gif';
    } else if (ext.endsWith('.svg')) {
      return 'image/svg+xml';
    } else if (ext.endsWith('.xml')) {
      return 'application/xml';
    } else if (ext.endsWith('.opf')) {
      return 'application/oebps-package+xml';
    } else if (ext.endsWith('.ncx')) {
      return 'application/x-dtbncx+xml';
    }
    return 'application/octet-stream';
  }

  void _initWebView() {
    if (_serverUrl == null || _isDisposed || !mounted) return;

    // No need to initialize controller here - it's created in build()
    setState(() {
      _isReady = true;
    });
  }

  void _onWebViewCreated(InAppWebViewController controller) {
    if (_isDisposed) {
      return;
    }

    _controller = controller;

    // Add JavaScript handler for Flutter bridge
    controller.addJavaScriptHandler(
      handlerName: 'FlutterBridge',
      callback: (args) {
        _handleJavaScriptMessage(args);
      },
    );

    // Store position to restore when book reports ready
    final savedCfi = widget.book.lastPositionCfi;
    if (savedCfi != null && savedCfi.isNotEmpty) {
      _pendingCfi = savedCfi;
      _pendingRestorePageHint = widget.restorePageHint;
      _pendingRestoreTotalPagesHint = widget.restoreTotalPagesHint;
      debugPrint('Will restore position when ready: $savedCfi');
    }

    // Wait for WebView to be fully loaded before opening book
    // The actual open will happen in onLoadStop
  }

  void _tryOpenBook(InAppWebViewController controller, {int retryCount = 0}) {
    if (_serverUrl == null || _isDisposed) return;

    const maxRetries = 5;

    controller
        .evaluateJavascript(
          source: '''
        (function() {
          if (typeof ePub === 'undefined' || !window.ReaderAPI) {
            return 'NOT_READY';
          }
          return 'READY';
        })();
      ''',
        )
        .then((result) {
          if (result == 'READY') {
            debugPrint('EPUB.js is ready, opening book...');
            _openBook(controller);
          } else if (retryCount < maxRetries) {
            debugPrint(
              'EPUB.js not ready yet, retrying... (${retryCount + 1}/$maxRetries)',
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_isDisposed) {
                return;
              }
              _tryOpenBook(controller, retryCount: retryCount + 1);
            });
          } else {
            debugPrint('EPUB.js failed to load after $maxRetries retries');
            // Try anyway as a last resort
            _openBook(controller);
          }
        });
  }

  void _openBook(InAppWebViewController controller) {
    if (_serverUrl == null || _isDisposed) return;

    controller.evaluateJavascript(
      source:
          '''
        (function() {
          console.log('=== BOOK OPEN ATTEMPT ===');
          console.log('Server URL: $_serverUrl');
          console.log('ePub available:', typeof ePub !== 'undefined');
          console.log('ReaderAPI available:', typeof window.ReaderAPI !== 'undefined');
          
          if (typeof ePub === 'undefined') {
            console.error('EPUB.js library not loaded');
            return 'EPUB_NOT_LOADED';
          }
          
          if (window.ReaderAPI && window.ReaderAPI.openBook) {
            try {
              console.log('Opening book from local server...');
              var result = window.ReaderAPI.openBook('$_serverUrl', {
                spread: ${widget.viewMode == PageViewMode.spread},
                fontSize: ${widget.fontSize},
                cacheKey: ${jsonEncode(widget.book.id)}
              });
              console.log('openBook returned:', result);
              return 'SUCCESS';
            } catch (e) {
              console.error('Error in openBook:', e.message);
              return 'ERROR: ' + e.message;
            }
          } else {
            console.error('ReaderAPI not available');
            return 'API_NOT_READY';
          }
        })();
      ''',
    );
  }

  void _restorePosition(
    String cfi, {
    int? pageHint,
    int? totalPagesHint,
  }) {
    final options = <String>[];
    if (pageHint != null) {
      options.add('pageHint: ${pageHint + 1}');
    }
    if (totalPagesHint != null) {
      options.add('totalPagesHint: $totalPagesHint');
    }
    final optionSource = options.isEmpty ? 'null' : '{${options.join(', ')}}';
    _evaluateJavascriptSafely(
      'window.ReaderAPI.restorePosition(${jsonEncode(cfi)}, $optionSource)',
    );
  }

  void _handleJavaScriptMessage(List<dynamic> args) {
    if (_isDisposed) {
      return;
    }

    try {
      if (args.isEmpty) return;

      final data = args[0] as Map<String, dynamic>;
      final type = data['type'] as String?;
      final payload = data['data'] as Map<String, dynamic>?;

      switch (type) {
        case 'bookReady':
          debugPrint('Book ready: ${payload?['title']}');
          _bookNavReady = true;
          // Restore position if we have a pending CFI
          if (_pendingCfi != null) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_isDisposed) {
                return;
              }
              _restorePosition(
                _pendingCfi!,
                pageHint: _pendingRestorePageHint,
                totalPagesHint: _pendingRestoreTotalPagesHint,
              );
              _pendingCfi = null;
              _pendingRestorePageHint = null;
              _pendingRestoreTotalPagesHint = null;
            });
          }
          break;

        case 'pageChanged':
          final currentPage = payload?['currentPage'] as int? ?? 1;
          final totalPages = payload?['totalPages'] as int? ?? 1;
          final cfi = payload?['cfi'] as String?;

          debugPrint('=== DART: pageChanged received ===');
          debugPrint('Current: $currentPage, Total: $totalPages');
          debugPrint('Payload: $payload');

          setState(() {
            _currentPage = currentPage;
            _totalPages = totalPages;
          });

          // Notify parent of total pages from EPUB
          if (widget.onTotalPagesChanged != null) {
            debugPrint('Calling onTotalPagesChanged with: $totalPages');
            widget.onTotalPagesChanged!(totalPages);
          } else {
            debugPrint('WARNING: onTotalPagesChanged is null!');
          }

          if (cfi != null && cfi.isNotEmpty) {
            widget.onPositionChanged?.call(cfi);
          }

          widget.onPageChanged?.call(currentPage - 1);
          break;

        case 'error':
          debugPrint('Reader error: ${payload?['message']}');
          break;

        case 'savePosition':
          final cfi = payload?['cfi'] as String?;
          if (cfi != null) {
            debugPrint('Saving position: $cfi');
            widget.onPositionChanged?.call(cfi);
          }
          break;

        case 'tableOfContents':
          // TOC is wrapped in {chapters: [...]} to ensure proper type for Dart
          final chapters = payload?['chapters'] as List<dynamic>?;
          if (chapters != null) {
            debugPrint('Received TOC with ${chapters.length} chapters');
            final parsedChapters = <Chapter>[];
            for (var i = 0; i < chapters.length; i++) {
              final rawChapter = chapters[i];
              if (rawChapter is! Map) {
                continue;
              }

              final title = rawChapter['label']?.toString().trim() ?? '';
              final href = rawChapter['href']?.toString().trim() ?? '';
              if (title.isEmpty || href.isEmpty) {
                continue;
              }

              parsedChapters.add(
                Chapter(
                  title: title,
                  href: href,
                  order: i,
                ),
              );
            }

            widget.onTableOfContentsChanged?.call(parsedChapters);
          }
          break;

        case 'safeRegions':
          final regions = payload?['regions'] as List<dynamic>?;
          if (regions != null) {
            final parsed = regions
                .whereType<Map>()
                .map(
                  (region) => ReaderSafeRegion.fromJson(
                    Map<String, dynamic>.from(region),
                  ),
                )
                .where(
                  (region) => region.width > 0.05 && region.height > 0.05,
                )
                .toList(growable: false);

            widget.onSafeRegionsChanged?.call(parsed);
          }
          break;
      }
    } catch (e) {
      debugPrint('Error handling JS message: $e');
    }
  }

  // Public methods for external navigation control
  void nextPage() {
    _evaluateJavascriptSafely('window.ReaderAPI.nextPage()');
  }

  void prevPage() {
    _evaluateJavascriptSafely('window.ReaderAPI.prevPage()');
  }

  void goToPage(int pageNumber) {
    _evaluateJavascriptSafely('window.ReaderAPI.goToPage($pageNumber)');
  }

  void goToHref(String href) {
    _evaluateJavascriptSafely("window.ReaderAPI.goToHref('$href')");
  }

  void restorePosition(String cfi, {int? pageHint, int? totalPagesHint}) {
    _restorePosition(
      cfi,
      pageHint: pageHint,
      totalPagesHint: totalPagesHint,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady || _serverUrl == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(
              'file:///android_asset/flutter_assets/assets/reader/index.html',
            ),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowFileAccess: true,
            allowUniversalAccessFromFileURLs: true,
            allowContentAccess: true,
            useShouldOverrideUrlLoading: true,
            useHybridComposition: true,
            supportZoom: false,
            builtInZoomControls: false,
            displayZoomControls: false,
            javaScriptCanOpenWindowsAutomatically: true,
            mediaPlaybackRequiresUserGesture: false,
          ),
          onWebViewCreated: _onWebViewCreated,
          onLoadStop: (controller, url) {
            debugPrint('Reader page loaded: $url');
            // Wait a moment for EPUB.js to initialize, then open book with retry
            Future.delayed(const Duration(milliseconds: 500), () {
              if (_isDisposed) {
                return;
              }
              _tryOpenBook(controller, retryCount: 0);
            });
          },
          onConsoleMessage: (controller, consoleMessage) {
            final level = consoleMessage.messageLevel.toString();
            debugPrint('[$level] WebView: ${consoleMessage.message}');
          },
        ),
      ],
    );
  }
}

/// Image-based book reader for picture books
class _ImageBookView extends StatelessWidget {
  final Book book;
  final PageController pageController;
  final PageViewMode viewMode;
  final Function(int)? onPageChanged;

  const _ImageBookView({
    required this.book,
    required this.pageController,
    required this.viewMode,
    this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (viewMode == PageViewMode.spread) {
      return _ImageSpreadView(
        book: book,
        pageController: pageController,
        onPageChanged: onPageChanged,
      );
    }
    return _ImageSingleView(
      book: book,
      pageController: pageController,
      onPageChanged: onPageChanged,
    );
  }
}

class _ImageSingleView extends StatelessWidget {
  final Book book;
  final PageController pageController;
  final Function(int)? onPageChanged;

  const _ImageSingleView({
    required this.book,
    required this.pageController,
    this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: pageController,
      physics: const ReaderSwipePhysics(),
      itemCount: book.totalPages,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final page = book.getPage(index);
        if (page == null) {
          return const Center(child: Text('Page not found'));
        }
        return _ImagePage(imagePath: page.imagePath);
      },
    );
  }
}

class _ImageSpreadView extends StatelessWidget {
  final Book book;
  final PageController pageController;
  final Function(int)? onPageChanged;

  const _ImageSpreadView({
    required this.book,
    required this.pageController,
    this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isOddTotalPages = book.totalPages % 2 != 0;
    final totalSpreads = (book.totalPages / 2).ceil();

    return PageView.builder(
      controller: pageController,
      physics: const ReaderSwipePhysics(),
      itemCount: totalSpreads,
      onPageChanged: (index) {
        onPageChanged?.call(index * 2);
      },
      itemBuilder: (context, spreadIndex) {
        final leftPageIndex = spreadIndex * 2;
        final rightPageIndex = leftPageIndex + 1;

        final leftPage = book.getPage(leftPageIndex);
        final rightPage = isOddTotalPages && spreadIndex == totalSpreads - 1
            ? null
            : book.getPage(rightPageIndex);

        return Row(
          children: [
            Expanded(
              child: _ImagePage(
                imagePath: leftPage?.imagePath ?? '',
                isPlaceholder: leftPage == null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ImagePage(
                imagePath: rightPage?.imagePath ?? '',
                isPlaceholder: rightPage == null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ImagePage extends StatelessWidget {
  final String imagePath;
  final bool isPlaceholder;

  const _ImagePage({required this.imagePath, this.isPlaceholder = false});

  @override
  Widget build(BuildContext context) {
    if (isPlaceholder || imagePath.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C2333),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        imagePath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[300],
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'Could not load',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
