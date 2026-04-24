#!/usr/bin/env dart
// Usage: dart tools/scan_backgrounds.dart
// This script scans assets/backgrounds/ and generates the background list

import 'dart:io';
import 'dart:convert';

void main() {
  final backgroundsDir = Directory('assets/backgrounds');

  if (!backgroundsDir.existsSync()) {
    print('❌ assets/backgrounds directory not found');
    exit(1);
  }

  final backgrounds = <String>[];

  // Scan for image files
  for (final file in backgroundsDir.listSync()) {
    if (file is File) {
      final ext = file.path.split('.').last.toLowerCase();
      if (['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
        final filename = file.path.split('/').last.split('\\').last;
        backgrounds.add("'assets/backgrounds/$filename'");
      }
    }
  }

  if (backgrounds.isEmpty) {
    print('⚠️  No background images found in assets/backgrounds/');
    exit(0);
  }

  // Generate the Dart code to paste into background_service.dart
  final output =
      '''
  // Default backgrounds - auto-generated from assets/backgrounds/
  // Run: dart tools/scan_backgrounds.dart to regenerate
  static const List<String> _defaultBackgrounds = [
    ${backgrounds.join(',\n    ')},
  ];'''
          .trim();

  print('✅ Found ${backgrounds.length} background(s):');
  for (final bg in backgrounds) {
    print('   • $bg');
  }
  print('\n📋 Copy this into background_service.dart:\n');
  print(output);

  // Also update the service file automatically
  _updateServiceFile(backgrounds);
}

void _updateServiceFile(List<String> backgrounds) {
  final serviceFile = File('lib/services/background_service.dart');

  if (!serviceFile.existsSync()) {
    print(
      '\n⚠️  Could not auto-update: lib/services/background_service.dart not found',
    );
    return;
  }

  var content = serviceFile.readAsStringSync();

  // Find and replace the _defaultBackgrounds list
  final pattern = RegExp(
    r'// Default backgrounds.*?static const List<String> _defaultBackgrounds = \[.*?\];',
    dotAll: true,
  );

  final replacement =
      '''// Default backgrounds - auto-generated from assets/backgrounds/
  // Run: dart tools/scan_backgrounds.dart to regenerate
  static const List<String> _defaultBackgrounds = [
    ${backgrounds.join(',\n    ')},
  ];'''
          .trim();

  if (pattern.hasMatch(content)) {
    content = content.replaceFirst(pattern, replacement);
    serviceFile.writeAsStringSync(content);
    print('\n✅ Auto-updated lib/services/background_service.dart');
  } else {
    print('\n⚠️  Could not auto-update: pattern not found in file');
    print('   Please manually update the _defaultBackgrounds list.');
  }
}
