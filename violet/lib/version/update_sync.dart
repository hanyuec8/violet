// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'package:violet/log/log.dart';
import 'package:violet/network/wrapper.dart' as http;

class UpdateSyncManager {
  static const String updateApiUrl =
      'https://api.github.com/repos/hanyuec8/violet/releases/latest';
  static const String releasePageUrl =
      'https://github.com/hanyuec8/violet/releases/latest';

  static bool enableSensitiveUpdate = true;

  // Current app version (v1.34.4-lite)
  static const int majorVersion = 1;
  static const int minorVersion = 34;
  static const int patchVersion = 4;

  static String get currentVersion =>
      '$majorVersion.$minorVersion.$patchVersion';

  static bool updateRequire = false;
  static String latestVersion = '';
  static String version = '';
  static String updateMessage = '';
  static String updateUrl = '';

  static bool _checkIsNewVersion(List<int> ver) {
    if (ver.isEmpty) return false;
    if (ver[0] > majorVersion) return true;
    if (ver[0] < majorVersion) return false;

    if (ver.length > 1) {
      if (ver[1] > minorVersion) return true;
      if (ver[1] < minorVersion) return false;
    }

    if (ver.length > 2 && enableSensitiveUpdate) {
      if (ver[2] > patchVersion) return true;
    }
    return false;
  }

  static Future<void> checkUpdateSync() async {
    try {
      final response = await http
          .get(
            updateApiUrl,
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode != 200) {
        Logger.warning(
          '[Update-check] GitHub API returned status ${response.statusCode}',
        );
        return;
      }

      final info = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (info['tag_name'] as String?) ?? '';
      latestVersion = tagName.replaceAll(RegExp(r'[^0-9.]'), '');
      version = latestVersion;

      // Extract version numbers like "1.34.4" from "v1.34.4-lite"
      final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(tagName);
      if (match != null) {
        final verNumbers = <int>[
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          if (match.group(3) != null) int.parse(match.group(3)!),
        ];

        if (_checkIsNewVersion(verNumbers)) {
          updateRequire = true;
          updateMessage = (info['name'] as String?) ?? tagName;

          // Find apk download url from assets
          final assets = info['assets'] as List<dynamic>?;
          if (assets != null && assets.isNotEmpty) {
            for (var asset in assets) {
              final name = (asset['name'] as String? ?? '').toLowerCase();
              if (name.endsWith('.apk')) {
                updateUrl = (asset['browser_download_url'] as String?) ?? '';
                break;
              }
            }
          }
          if (updateUrl.isEmpty) {
            updateUrl = releasePageUrl;
          }
        }
      }
    } catch (e, st) {
      Logger.error('[Update-check] E: $e\n$st');
    }
  }
}
