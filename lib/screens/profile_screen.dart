import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_version.dart';
import '../theme.dart';
import '../services/app_info_service.dart';
import '../services/background_service.dart';
import '../services/character_service.dart';
import '../services/reading_stats_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showCharacters = true;
  bool _autoPlayAnimations = true;
  double _animationScale = 1.0;
  bool _fullScreenMode = true;
  bool _showStatsWidget = true;
  String _displayVersion = appVersion;
  final AppInfoService _appInfoService = AppInfoService();
  final BackgroundService _backgroundService = BackgroundService();
  final CharacterService _characterService = CharacterService();
  final ReadingStatsService _statsService = ReadingStatsService();
  String? _currentBackground;
  List<String> _availableBackgrounds = [];
  bool _isLoading = true;
  bool _rotationEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadAppInfo();
    await _loadBackgroundData();
    await _loadStatsSettings();
    await _loadCharacterSettings();
  }

  Future<void> _loadAppInfo() async {
    final version = await _appInfoService.getDisplayVersion();
    if (!mounted) {
      return;
    }

    setState(() {
      _displayVersion = version;
    });
  }

  Future<void> _loadCharacterSettings() async {
    final showCharacters = await _characterService.getShowCharacters();
    final autoPlayAnimations = await _characterService.getAutoPlayAnimations();
    final animationScale = await _characterService.getAnimationScale();
    if (!mounted) {
      return;
    }

    setState(() {
      _showCharacters = showCharacters;
      _autoPlayAnimations = autoPlayAnimations;
      _animationScale = animationScale;
    });
  }

  Future<void> _loadStatsSettings() async {
    await _statsService.init();
    final showStats = await _statsService.getShowStatsWidget();
    setState(() {
      _showStatsWidget = showStats;
    });
  }

  Future<void> _loadBackgroundData() async {
    await _backgroundService.init();
    final backgrounds = await _backgroundService.getAvailableBackgrounds();
    final current = await _backgroundService.getCurrentBackground();
    final rotationEnabled = _backgroundService.isRotationEnabled();

    setState(() {
      _availableBackgrounds = backgrounds;
      _currentBackground = current;
      _rotationEnabled = rotationEnabled;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Parent settings and preferences',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            _SettingsSection(
              title: 'App Background',
              children: [
                _SettingsTile(
                  icon: Icons.wallpaper,
                  title: 'Select Background',
                  subtitle: _isLoading
                      ? 'Loading backgrounds...'
                      : '${_availableBackgrounds.length} backgrounds available',
                  onTap: () => _showBackgroundPicker(context),
                  trailing: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      : Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                            image: _currentBackground != null
                                ? DecorationImage(
                                    image: _currentBackground!.startsWith('/')
                                        ? FileImage(File(_currentBackground!))
                                        : AssetImage(_currentBackground!)
                                              as ImageProvider,
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                        ),
                ),
                _SettingsTile(
                  icon: Icons.import_export,
                  title: 'Import Custom Background',
                  subtitle: 'Add your own background image',
                  onTap: () => _importBackground(),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.autorenew,
                  title: 'Auto-Rotate Backgrounds',
                  subtitle: 'Change background automatically',
                  trailing: Switch(
                    value: _rotationEnabled,
                    onChanged: (v) async {
                      await _backgroundService.setRotationEnabled(v);
                      setState(() => _rotationEnabled = v);
                    },
                    activeColor: AppTheme.primaryOrange,
                  ),
                ),
                ...(_rotationEnabled
                    ? [
                        _SettingsTile(
                          icon: Icons.timer,
                          title: 'Rotation Interval',
                          subtitle: 'How often to change backgrounds',
                          onTap: () => _showRotationIntervalDialog(context),
                          trailing: Text(
                            _getRotationIntervalText(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ]
                    : []),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'Reading Experience',
              children: [
                _SettingsTile(
                  icon: Icons.face,
                  title: 'Show Characters',
                  subtitle: 'Display animated characters while reading',
                  trailing: Switch(
                    value: _showCharacters,
                    onChanged: (v) async {
                      await _characterService.setShowCharacters(v);
                      if (!mounted) {
                        return;
                      }
                      setState(() => _showCharacters = v);
                    },
                    activeColor: AppTheme.primaryOrange,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.play_circle,
                  title: 'Auto-Play Animations',
                  subtitle: 'Characters animate automatically',
                  trailing: Switch(
                    value: _autoPlayAnimations,
                    onChanged: (v) async {
                      await _characterService.setAutoPlayAnimations(v);
                      if (!mounted) {
                        return;
                      }
                      setState(() => _autoPlayAnimations = v);
                    },
                    activeColor: AppTheme.primaryOrange,
                  ),
                ),
                _SettingsSliderTile(
                  icon: Icons.zoom_out_map,
                  title: 'Animation Scale',
                  subtitle: '${(_animationScale * 100).round()}%',
                  value: _animationScale,
                  min: 0.7,
                  max: 3.0,
                  divisions: 23,
                  onChanged: (value) {
                    setState(() => _animationScale = value);
                  },
                  onChangeEnd: (value) async {
                    await _characterService.setAnimationScale(value);
                  },
                ),
                _SettingsTile(
                  icon: Icons.fullscreen,
                  title: 'Full Screen Mode',
                  subtitle: 'Hide system UI while reading',
                  trailing: Switch(
                    value: _fullScreenMode,
                    onChanged: (v) => setState(() => _fullScreenMode = v),
                    activeColor: AppTheme.primaryOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'Content Management',
              children: [
                _SettingsTile(
                  icon: Icons.add_circle,
                  title: 'Import Book',
                  subtitle: 'Add a new book to your library',
                  onTap: () => _showImportDialog(context),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.palette,
                  title: 'Manage Characters',
                  subtitle: 'Add or remove character packs',
                  onTap: () => _showComingSoon(context),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.folder,
                  title: 'Storage Location',
                  subtitle: 'Choose where books are stored',
                  onTap: () => _showStorageDialog(context),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'Stats & Analytics',
              children: [
                _SettingsTile(
                  icon: Icons.show_chart,
                  title: 'Show Stats Widget',
                  subtitle: 'Display reading stats on home screen',
                  trailing: Switch(
                    value: _showStatsWidget,
                    onChanged: (v) async {
                      await _statsService.setShowStatsWidget(v);
                      setState(() => _showStatsWidget = v);
                    },
                    activeColor: AppTheme.primaryOrange,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.restore,
                  title: 'Reset Stats',
                  subtitle: 'Clear all reading statistics',
                  onTap: () => _showResetStatsDialog(context),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SettingsSection(
              title: 'About',
              children: [
                _SettingsTile(
                  icon: Icons.info,
                  title: 'Storytime Reader',
                  subtitle: 'Version $_displayVersion',
                  trailing: const SizedBox(),
                ),
                _SettingsTile(
                  icon: Icons.help,
                  title: 'Help & Support',
                  subtitle: 'Get help using the app',
                  onTap: () => _showHelpDialog(context),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBlueMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Help & Features',
          style: TextStyle(color: Colors.white),
        ),
        content: const SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _HelpSection(
                  title: 'Home',
                  items: [
                    'Continue Reading shows books you have opened and have not finished.',
                    'Reading Stats tracks books in progress and books finished this month.',
                    'Quick Find Library searches across your saved books.',
                  ],
                ),
                _HelpSection(
                  title: 'Library',
                  items: [
                    'Open bundled books and imported EPUB books from one shelf.',
                    'Use search and filters to narrow the shelf by status or format.',
                    'Reading progress is saved on this device for offline use.',
                  ],
                ),
                _HelpSection(
                  title: 'Reader',
                  items: [
                    'Use the page arrows or page indicator to move through a book.',
                    'Text controls adjust reading display for EPUB books.',
                    'Book position, progress, and finished status are saved automatically.',
                  ],
                ),
                _HelpSection(
                  title: 'Characters',
                  items: [
                    'Character animation starts after the book finishes loading.',
                    'Drag the character anywhere on the page; release to let it react and sprint away.',
                    'Use Profile settings to turn characters on or off, enable auto-play, and change animation scale.',
                  ],
                ),
                _HelpSection(
                  title: 'Discover',
                  items: [
                    'Project Gutenberg opens in your browser for free public domain classics.',
                    'Downloaded or imported books remain available offline after they are stored in the app.',
                  ],
                ),
                _HelpSection(
                  title: 'Profile',
                  items: [
                    'Choose app backgrounds, import a custom background, or rotate backgrounds automatically.',
                    'Show or hide the home stats widget.',
                    'Reset reading statistics when you want to start fresh.',
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B3D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Import Book', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Supported formats:\n• Image folders (ZIP)\n• Image folders\n\nComing soon:\n• PDF files\n• EPUB files',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Import feature coming soon!'),
                  backgroundColor: Color(0xFFFF9900),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Browse Files'),
          ),
        ],
      ),
    );
  }

  void _showStorageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1B3D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Storage Location',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Books are currently stored in app-private storage.\n\nYou can change this to store books in a shared folder that survives app reinstalls.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Storage settings coming soon!'),
                  backgroundColor: Color(0xFFFF9900),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Choose Folder'),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This feature is coming soon!'),
        backgroundColor: Color(0xFFFF9900),
      ),
    );
  }

  Future<void> _showBackgroundPicker(BuildContext context) async {
    // Show loading indicator while fetching backgrounds
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryOrange),
      ),
    );

    try {
      final backgrounds = await _backgroundService.getAvailableBackgrounds();
      final current = _backgroundService.getDefaultBackground();

      // Load all animation styles upfront
      final Map<String, String> styles = {};
      for (final bg in backgrounds) {
        styles[bg] = await _backgroundService.getAnimationStyle(bg);
      }

      // Remove loading dialog
      Navigator.pop(context);

      if (backgrounds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No backgrounds available. Add PNG files to assets/backgrounds/',
            ),
            backgroundColor: AppTheme.darkBlueLight,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Use StatefulBuilder to allow dialog content to rebuild
      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: AppTheme.darkBlueMid,
            title: const Text(
              'Select Background',
              style: TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: backgrounds.length <= 3 ? 160 : 340,
              child: Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                thickness: 8,
                radius: const Radius.circular(4),
                child: GridView.builder(
                  padding: const EdgeInsets.only(right: 16, bottom: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: backgrounds.length,
                  itemBuilder: (context, index) {
                    final bg = backgrounds[index];
                    final isSelected = bg == current;
                    final isCustom = bg.startsWith('/');
                    final style = styles[bg] ?? 'default';

                    return GestureDetector(
                      onTap: () async {
                        await _backgroundService.setDefaultBackground(bg);
                        Navigator.pop(context);
                        setState(() => _currentBackground = bg);

                        // Show live update notice
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Background updated!'),
                            backgroundColor: AppTheme.darkBlueLight,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      onLongPress: () =>
                          _showStyleSelector(context, bg, style, (newStyle) {
                            // Update the local styles map and rebuild dialog
                            setDialogState(() {
                              styles[bg] = newStyle;
                            });
                          }),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryOrange
                                    : Colors.white.withOpacity(0.3),
                                width: isSelected ? 3 : 1,
                              ),
                              image: DecorationImage(
                                image: isCustom
                                    ? FileImage(File(bg))
                                    : AssetImage(bg) as ImageProvider,
                                fit: BoxFit.cover,
                              ),
                            ),
                            child: isSelected
                                ? Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.check_circle,
                                        color: AppTheme.primaryOrange,
                                        size: 32,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          // Animation style badge
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                style.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          // Delete button for custom backgrounds
                          if (isCustom)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: AppTheme.darkBlueMid,
                                      title: const Text(
                                        'Delete Background?',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: const Text(
                                        'This will permanently remove this custom background.',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(
                                            'Cancel',
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                0.7,
                                              ),
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await _backgroundService
                                        .deleteCustomBackground(bg);
                                    setState(() {
                                      _availableBackgrounds.remove(bg);
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // Remove loading dialog if still showing
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      print('Error loading backgrounds: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading backgrounds: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _importBackground() async {
    final path = await _backgroundService.importBackground();
    if (path != null) {
      setState(() {
        _availableBackgrounds.add(path);
        _currentBackground = path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Background imported successfully!'),
          backgroundColor: AppTheme.darkBlueLight,
          action: SnackBarAction(
            label: 'SET',
            textColor: AppTheme.primaryOrange,
            onPressed: () async {
              await _backgroundService.setDefaultBackground(path);
              setState(() => _currentBackground = path);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Background updated!'),
                  backgroundColor: AppTheme.darkBlueLight,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  void _showRotationIntervalDialog(BuildContext context) {
    final intervals = [
      ('startup', 'Every App Launch'),
      ('hourly', 'Every Hour'),
      ('daily', 'Daily'),
      ('weekly', 'Weekly'),
    ];

    final current = _backgroundService.getRotationInterval();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBlueMid,
        title: const Text(
          'Rotation Interval',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: intervals.map((interval) {
            return ListTile(
              title: Text(
                interval.$2,
                style: const TextStyle(color: Colors.white),
              ),
              trailing: interval.$1 == current
                  ? const Icon(Icons.check, color: AppTheme.primaryOrange)
                  : null,
              onTap: () async {
                await _backgroundService.setRotationInterval(interval.$1);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  void _showStyleSelector(
    BuildContext context,
    String backgroundPath,
    String currentStyle,
    Function(String) onStyleChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBlueMid,
        title: const Text(
          'Select Animation Style',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: BackgroundService.animationStyles.map((style) {
            final isSelected = style == currentStyle;
            IconData icon;
            String label;

            switch (style) {
              case 'pokemon':
                icon = Icons.catching_pokemon;
                label = 'Pokemon';
                break;
              default:
                icon = Icons.style;
                label = 'Default';
            }

            return ListTile(
              leading: Icon(
                icon,
                color: isSelected ? AppTheme.primaryOrange : Colors.white70,
              ),
              title: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.primaryOrange : Colors.white,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: isSelected
                  ? const Icon(Icons.check, color: AppTheme.primaryOrange)
                  : null,
              onTap: () async {
                await _backgroundService.setAnimationStyle(
                  backgroundPath,
                  style,
                );

                // Close the style selector dialog
                Navigator.pop(context);

                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Animation style set to $label'),
                    backgroundColor: AppTheme.darkBlueLight,
                    duration: const Duration(seconds: 2),
                  ),
                );

                // Call the callback with the new style so parent can update
                onStyleChanged(style);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  String _getRotationIntervalText() {
    switch (_backgroundService.getRotationInterval()) {
      case 'startup':
        return 'Every Launch';
      case 'hourly':
        return 'Every Hour';
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      default:
        return 'Every Launch';
    }
  }

  void _showResetStatsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkBlueMid,
        title: const Text('Reset Stats', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will clear all your reading statistics. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
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
            onPressed: () async {
              await _statsService.resetStats();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Statistics reset successfully'),
                  backgroundColor: AppTheme.darkBlueLight,
                ),
              );
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _HelpSection extends StatelessWidget {
  final String title;
  final List<String> items;

  const _HelpSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => _HelpBullet(text: item)),
        ],
      ),
    );
  }
}

class _HelpBullet extends StatelessWidget {
  final String text;

  const _HelpBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '- ',
            style: TextStyle(
              color: AppTheme.primaryOrange.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(children: children),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppTheme.primaryOrange, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SettingsSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.primaryOrange, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  activeColor: AppTheme.primaryOrange,
                  inactiveColor: Colors.white.withValues(alpha: 0.18),
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
