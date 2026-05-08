import 'package:flutter/services.dart';
import '../app_version.dart';

class AppInfoService {
  static const MethodChannel _channel = MethodChannel('e_reader/app_info');

  Future<String> getDisplayVersion() async {
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'getVersion',
      );
      final versionName = info?['versionName']?.toString();
      final versionCode = info?['versionCode']?.toString();

      if (versionName != null && versionName.isNotEmpty) {
        if (versionCode != null && versionCode.isNotEmpty) {
          return '$versionName+$versionCode';
        }
        return versionName;
      }
    } catch (_) {
      // Desktop/debug fallback when the Android package channel is unavailable.
    }

    return appVersion;
  }
}
