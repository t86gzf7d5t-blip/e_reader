import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class BackgroundService extends ChangeNotifier {
  static const String _prefsKey = 'background_settings';
  static const String _defaultBackgroundKey = 'default_background';
  static const String _rotationEnabledKey = 'rotation_enabled';
  static const String _rotationIntervalKey = 'rotation_interval';
  static const String _lastRotationKey = 'last_rotation';
  static const String _customBackgroundsKey = 'custom_backgrounds';
  static const String _backgroundStylesKey = 'background_styles';

  // Animation styles available
  static const List<String> animationStyles = ['pokemon', 'default'];

  // Default backgrounds - will be auto-scanned on startup
  List<String> _defaultBackgrounds = [];
  List<String>? _cachedDefaultBackgrounds;

  SharedPreferences? _prefs;
  String? _currentBackground;
  DateTime? _lastRotation;

  // Current background getter
  String? get currentBackground => _currentBackground;

  // Singleton pattern
  static final BackgroundService _instance = BackgroundService._internal();
  factory BackgroundService() => _instance;
  BackgroundService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _lastRotation = DateTime.tryParse(
      _prefs?.getString(_lastRotationKey) ?? '',
    );
    // Auto-scan backgrounds on startup
    await _scanAssetBackgrounds();
  }

  /// Auto-scan assets/backgrounds folder for new images
  Future<void> _scanAssetBackgrounds() async {
    final scanned = <String>[];

    // Try to read AssetManifest if available
    try {
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifest);

      for (final key in manifestMap.keys) {
        if (key.startsWith('assets/backgrounds/') &&
            (key.toLowerCase().endsWith('.png') ||
                key.toLowerCase().endsWith('.jpg') ||
                key.toLowerCase().endsWith('.jpeg'))) {
          scanned.add(key);
        }
      }
    } catch (e) {
      print('AssetManifest not available, using fallback scan');
    }

    // If manifest didn't work, try all known background filenames
    if (scanned.isEmpty) {
      final testFiles = [
        'assets/backgrounds/Mountain path to Victory Road.png',
        'assets/backgrounds/Idyllic countryside village under a blue sky.png',
        'assets/backgrounds/Charming village by the serene pond_1.png',
        'assets/backgrounds/Ninja village with stone faces.png',
        'assets/backgrounds/Coastal town with aquatic gym.png',
        'assets/backgrounds/Mountain town with stone gym.png',
      ];

      for (final path in testFiles) {
        try {
          await rootBundle.load(path);
          scanned.add(path);
        } catch (e) {
          // File doesn't exist
        }
      }
    }

    _defaultBackgrounds = scanned;
    print('Auto-scanned ${_defaultBackgrounds.length} backgrounds');
  }

  /// Get animation style for a background
  Future<String> getAnimationStyle(String backgroundPath) async {
    // Ensure prefs is initialized
    if (_prefs == null) {
      await init();
    }

    final styles = _prefs?.getString(_backgroundStylesKey);
    if (styles != null) {
      final Map<String, dynamic> styleMap = json.decode(styles);
      final style = styleMap[backgroundPath] ?? 'default';
      return animationStyles.contains(style) ? style : 'default';
    }
    return 'default';
  }

  /// Set animation style for a background
  Future<void> setAnimationStyle(String backgroundPath, String style) async {
    final normalizedStyle = animationStyles.contains(style) ? style : 'default';
    final existing = _prefs?.getString(_backgroundStylesKey);
    Map<String, dynamic> styleMap = {};

    if (existing != null) {
      styleMap = Map<String, dynamic>.from(json.decode(existing));
    }

    styleMap[backgroundPath] = normalizedStyle;
    await _prefs?.setString(_backgroundStylesKey, json.encode(styleMap));
    notifyListeners();
  }

  /// Get current background's animation style
  Future<String> getCurrentAnimationStyle() async {
    final current =
        _currentBackground ?? _prefs?.getString(_defaultBackgroundKey);
    if (current != null) {
      return await getAnimationStyle(current);
    }
    return 'default';
  }

  /// Get the current background image path
  Future<String> getCurrentBackground() async {
    await init();

    // Check if rotation is enabled and time to rotate
    if (isRotationEnabled()) {
      final shouldRotate = _shouldRotate();
      if (shouldRotate) {
        await _rotateBackground();
      }
    }

    // Get the selected background
    final selected = _prefs?.getString(_defaultBackgroundKey);
    if (selected != null && selected.isNotEmpty) {
      // Check if it's a custom background (stored in app directory)
      if (selected.startsWith('/')) {
        final file = File(selected);
        if (await file.exists()) {
          _currentBackground = selected;
          return selected;
        }
      } else {
        // It's an asset path
        try {
          await rootBundle.load(selected).timeout(const Duration(seconds: 2));
          _currentBackground = selected;
          return selected;
        } catch (e) {
          print('Asset not found or timed out: $selected');
        }
      }
    }

    // Return first available default background as fallback
    try {
      final defaults = await _getDefaultBackgrounds().timeout(
        const Duration(seconds: 3),
      );
      if (defaults.isNotEmpty) {
        // Auto-select first background on first boot
        if (selected == null || selected.isEmpty) {
          await setDefaultBackground(defaults.first);
        }
        return defaults.first;
      }
    } catch (e) {
      print('Error getting default backgrounds: $e');
    }

    // Return empty string if no backgrounds exist (will use gradient fallback)
    return '';
  }

  /// Check if we should rotate the background
  bool _shouldRotate() {
    final interval = getRotationInterval();
    if (_lastRotation == null) return true;

    final now = DateTime.now();
    final difference = now.difference(_lastRotation!);

    switch (interval) {
      case 'startup':
        return true; // Rotate every app launch
      case 'hourly':
        return difference.inHours >= 1;
      case 'daily':
        return difference.inDays >= 1;
      case 'weekly':
        return difference.inDays >= 7;
      default:
        return false;
    }
  }

  /// Rotate to the next background
  Future<void> _rotateBackground() async {
    final available = await getAvailableBackgrounds();
    if (available.isEmpty) return;

    final current = _prefs?.getString(_defaultBackgroundKey);
    int currentIndex = 0;

    if (current != null) {
      currentIndex = available.indexOf(current);
      if (currentIndex == -1) currentIndex = 0;
    }

    // Move to next background
    final nextIndex = (currentIndex + 1) % available.length;
    final nextBackground = available[nextIndex];

    await setDefaultBackground(nextBackground);
    _lastRotation = DateTime.now();
    await _prefs?.setString(_lastRotationKey, _lastRotation!.toIso8601String());
  }

  /// Get all available backgrounds (default + custom)
  Future<List<String>> getAvailableBackgrounds() async {
    final List<String> backgrounds = [];

    // Add default asset backgrounds (try each one individually)
    for (final bgPath in _defaultBackgrounds) {
      try {
        await rootBundle.load(bgPath).timeout(const Duration(seconds: 1));
        backgrounds.add(bgPath);
      } catch (e) {
        // Asset doesn't exist or timed out, skip it
        print('Background not found: $bgPath');
      }
    }

    // Add custom backgrounds from app directory
    final customBackgrounds =
        _prefs?.getStringList(_customBackgroundsKey) ?? [];
    for (final customBg in customBackgrounds) {
      final file = File(customBg);
      if (await file.exists()) {
        backgrounds.add(customBg);
      }
    }

    return backgrounds;
  }

  /// Get list of default backgrounds (hardcoded for reliability)
  Future<List<String>> _getDefaultBackgrounds() async {
    if (_cachedDefaultBackgrounds != null) {
      return _cachedDefaultBackgrounds!;
    }

    final List<String> validBackgrounds = [];

    // Test each hardcoded background to see if it exists
    for (final bgPath in _defaultBackgrounds) {
      try {
        await rootBundle.load(bgPath).timeout(const Duration(seconds: 1));
        validBackgrounds.add(bgPath);
      } catch (e) {
        print('Background asset not found: $bgPath');
      }
    }

    _cachedDefaultBackgrounds = validBackgrounds;
    return validBackgrounds;
  }

  /// Set the default background
  Future<void> setDefaultBackground(String path) async {
    await _prefs?.setString(_defaultBackgroundKey, path);
    _currentBackground = path;
    notifyListeners(); // Notify AppShell to rebuild with new background
  }

  /// Get the current default background path
  String? getDefaultBackground() {
    return _prefs?.getString(_defaultBackgroundKey);
  }

  /// Check if rotation is enabled
  bool isRotationEnabled() {
    return _prefs?.getBool(_rotationEnabledKey) ?? false;
  }

  /// Enable/disable rotation
  Future<void> setRotationEnabled(bool enabled) async {
    await _prefs?.setBool(_rotationEnabledKey, enabled);
    if (enabled) {
      _lastRotation = DateTime.now();
      await _prefs?.setString(
        _lastRotationKey,
        _lastRotation!.toIso8601String(),
      );
    }
  }

  /// Get rotation interval
  String getRotationInterval() {
    return _prefs?.getString(_rotationIntervalKey) ?? 'startup';
  }

  /// Set rotation interval
  Future<void> setRotationInterval(String interval) async {
    await _prefs?.setString(_rotationIntervalKey, interval);
  }

  /// Import a custom background image
  Future<String?> importBackground() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      if (file.path == null) return null;

      // Copy to app directory
      final appDir = await getApplicationDocumentsDirectory();
      final backgroundsDir = Directory('${appDir.path}/backgrounds');

      if (!await backgroundsDir.exists()) {
        await backgroundsDir.create(recursive: true);
      }

      final fileName = 'custom_${DateTime.now().millisecondsSinceEpoch}.png';
      final destPath = '${backgroundsDir.path}/$fileName';

      await File(file.path!).copy(destPath);

      // Add to custom backgrounds list
      final customBackgrounds =
          _prefs?.getStringList(_customBackgroundsKey) ?? [];
      customBackgrounds.add(destPath);
      await _prefs?.setStringList(_customBackgroundsKey, customBackgrounds);

      return destPath;
    } catch (e) {
      print('Error importing background: $e');
      return null;
    }
  }

  /// Delete a custom background
  Future<void> deleteCustomBackground(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      // Remove from list
      final customBackgrounds =
          _prefs?.getStringList(_customBackgroundsKey) ?? [];
      customBackgrounds.remove(path);
      await _prefs?.setStringList(_customBackgroundsKey, customBackgrounds);

      // If this was the current background, reset to default
      final current = _prefs?.getString(_defaultBackgroundKey);
      if (current == path) {
        final available = await getAvailableBackgrounds();
        if (available.isNotEmpty) {
          await setDefaultBackground(available.first);
        }
      }
    } catch (e) {
      print('Error deleting background: $e');
    }
  }

  /// Get a display name for a background
  String getBackgroundName(String path) {
    if (path.startsWith('assets/')) {
      // Extract filename without extension
      final fileName = path.split('/').last;
      return fileName.replaceAll('.png', '').replaceAll('_', ' ').toUpperCase();
    } else {
      // Custom background
      return 'Custom ${path.split('_').last.replaceAll('.png', '')}';
    }
  }

  /// Get the total count of available backgrounds
  Future<int> getBackgroundCount() async {
    final backgrounds = await getAvailableBackgrounds();
    return backgrounds.length;
  }
}
