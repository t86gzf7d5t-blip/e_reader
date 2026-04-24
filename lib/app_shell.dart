import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/profile_screen.dart';
import 'services/background_service.dart';
import 'widgets/reader_swipe_physics.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  final BackgroundService _backgroundService = BackgroundService();
  String? _backgroundPath;
  bool _isLoadingBackground = true;
  late PageController _pageController;

  final List<Widget> _screens = const [
    HomeScreen(),
    LibraryScreen(),
    DiscoverScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    // Start background loading but don't block the UI
    _loadBackground();
    // Listen for background changes
    _backgroundService.addListener(_onBackgroundChanged);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _backgroundService.removeListener(_onBackgroundChanged);
    super.dispose();
  }

  void _onBackgroundChanged() {
    if (mounted) {
      setState(() {
        _backgroundPath = _backgroundService.currentBackground;
      });
    }
  }

  Future<void> _loadBackground() async {
    try {
      // Add timeout to prevent hanging - increased to 10s for slower devices
      final path = await _backgroundService.getCurrentBackground().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('Background loading timed out');
          return '';
        },
      );
      if (mounted) {
        setState(() {
          _backgroundPath = path.isEmpty ? null : path;
          _isLoadingBackground = false;
        });
      }
    } catch (e) {
      print('Error loading background: $e');
      if (mounted) {
        setState(() {
          _backgroundPath = null;
          _isLoadingBackground = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't block the UI while loading background - show gradient initially
    return Container(
      decoration: _buildBackgroundDecoration(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: Colors.transparent,
        body: PageView(
          controller: _pageController,
          physics: const ReaderSwipePhysics(),
          onPageChanged: (index) {
            setState(() => _currentIndex = index);
          },
          children: _screens,
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  void _navigateToPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    setState(() => _currentIndex = index);
  }

  BoxDecoration _buildBackgroundDecoration() {
    if (_backgroundPath == null) {
      return const BoxDecoration(gradient: AppTheme.mainBackground);
    }

    // Check if it's a file path or asset path
    if (_backgroundPath!.startsWith('/')) {
      // Custom file background
      return BoxDecoration(
        image: DecorationImage(
          image: FileImage(File(_backgroundPath!)),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.3),
            BlendMode.darken,
          ),
        ),
      );
    } else {
      // Asset background
      return BoxDecoration(
        image: DecorationImage(
          image: AssetImage(_backgroundPath!),
          fit: BoxFit.cover,
          colorFilter: ColorFilter.mode(
            Colors.black.withOpacity(0.3),
            BlendMode.darken,
          ),
        ),
      );
    }
  }

  Widget _buildBottomNav() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: _currentIndex == 0,
                  onTap: () => _navigateToPage(0),
                ),
                _NavItem(
                  icon: Icons.library_books_rounded,
                  label: 'Library',
                  isSelected: _currentIndex == 1,
                  onTap: () => _navigateToPage(1),
                ),
                _NavItem(
                  icon: Icons.explore_rounded,
                  label: 'Discover',
                  isSelected: _currentIndex == 2,
                  onTap: () => _navigateToPage(2),
                ),
                _NavItem(
                  icon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: _currentIndex == 3,
                  onTap: () => _navigateToPage(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [AppTheme.primaryOrange, AppTheme.secondaryOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryOrange.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white54,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
