import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/character.dart';

class CharacterService {
  static const String _showCharactersKey = 'reader_show_characters';
  static const String _autoPlayAnimationsKey = 'reader_auto_play_animations';

  Future<bool> getShowCharacters() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_showCharactersKey) ?? true;
  }

  Future<void> setShowCharacters(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showCharactersKey, value);
  }

  Future<bool> getAutoPlayAnimations() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPlayAnimationsKey) ?? true;
  }

  Future<void> setAutoPlayAnimations(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPlayAnimationsKey, value);
  }

  Future<List<CharacterManifest>> loadAvailableCharactersForStyle(
    String styleKey,
  ) async {
    try {
      return [
        await _loadManifest(
          'assets/characters/character_a/storybook/manifest.json',
        ),
      ];
    } catch (_) {}

    final styleDirectory = _styleDirectoryFor(styleKey);
    try {
      return [
        await _loadManifest(
          'assets/characters/character_a/$styleDirectory/manifest.json',
        ),
      ];
    } catch (_) {
      return [ _loadPlaceholderCharacters().first ];
    }
  }

  String _styleDirectoryFor(String styleKey) {
    switch (styleKey) {
      case 'pokemon':
        return 'monster_adventure';
      case 'naruto':
        return 'ninja_anime';
      case 'ghibli':
        return 'cozy_watercolor';
      default:
        return 'storybook';
    }
  }

  CharacterStyle _parseStyle(String style) {
    switch (style) {
      case 'monster_adventure':
        return CharacterStyle.monsterAdventure;
      case 'ninja_anime':
        return CharacterStyle.ninjaAnime;
      case 'cozy_watercolor':
        return CharacterStyle.cozyWatercolor;
      default:
        return CharacterStyle.storybook;
    }
  }

  Future<CharacterManifest> _loadManifest(String assetPath) async {
    final manifestSource = await rootBundle.loadString(assetPath);
    final manifestJson = json.decode(manifestSource) as Map<String, dynamic>;
    final assetDirectory = assetPath.substring(0, assetPath.lastIndexOf('/'));

    final animationsJson =
        manifestJson['animations'] as Map<String, dynamic>? ?? const {};
    final animations = <String, CharacterAnimationClip>{};

    for (final entry in animationsJson.entries) {
      final value = entry.value as Map<String, dynamic>? ?? const {};
      final frames =
          (value['frames'] as List<dynamic>? ?? const [])
              .map((frame) => '$assetDirectory/${frame.toString()}')
              .toList(growable: false);
      animations[entry.key] = CharacterAnimationClip(
        id: entry.key,
        frames: frames,
        fps: (value['fps'] as num?)?.toInt() ?? 4,
        loop: value['loop'] as bool? ?? true,
      );
    }

    return CharacterManifest(
      id: manifestJson['characterId']?.toString() ?? 'unknown',
      name: manifestJson['displayName']?.toString() ?? 'Character',
      role: manifestJson['role']?.toString() ?? 'mom',
      style: _parseStyle(manifestJson['style']?.toString() ?? 'storybook'),
      defaultPosition:
          manifestJson['defaultPosition']?.toString() ?? 'bottomLeft',
      scale: (manifestJson['scale'] as num?)?.toDouble() ?? 0.22,
      animations: animations,
    );
  }

  List<CharacterManifest> _loadPlaceholderCharacters() {
    const placeholderAnimationsA = {
      'IDLE': CharacterAnimationClip(
        id: 'IDLE',
        frames: [
          'assets/characters/placeholder/idle_1.png',
          'assets/characters/placeholder/idle_2.png',
        ],
        fps: 4,
        loop: true,
      ),
    };
    const placeholderAnimationsB = {
      'IDLE': CharacterAnimationClip(
        id: 'IDLE',
        frames: [
          'assets/characters/placeholder/idle_2.png',
          'assets/characters/placeholder/idle_1.png',
        ],
        fps: 4,
        loop: true,
      ),
    };

    return const [
      CharacterManifest(
        id: 'young_dad',
        name: 'Young Dad',
        role: 'dad',
        style: CharacterStyle.storybook,
        defaultPosition: 'bottomLeft',
        scale: 0.22,
        animations: placeholderAnimationsA,
      ),
      CharacterManifest(
        id: 'young_mom',
        name: 'Young Mom',
        role: 'mom',
        style: CharacterStyle.storybook,
        defaultPosition: 'bottomRight',
        scale: 0.22,
        animations: placeholderAnimationsB,
      ),
    ];
  }
}
