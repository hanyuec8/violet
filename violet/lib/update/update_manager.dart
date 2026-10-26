// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:violet/network/wrapper.dart' as http;
import 'package:violet/pages/common/toast.dart';
import 'package:violet/version/update_sync.dart';

class UpdateManager {
  static Future<void> updateCheck(BuildContext context) async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    await UpdateSyncManager.checkUpdateSync();

    if (UpdateSyncManager.updateRequire && context.mounted) {
      showUpdateDialog(context);
    }
  }

  static Future<void> showUpdateDialog(BuildContext context) async {
    final newVersion = UpdateSyncManager.version;
    final title = UpdateSyncManager.updateMessage.isNotEmpty
        ? UpdateSyncManager.updateMessage
        : '새로운 업데이트 ($newVersion)';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '최신 버전 ($newVersion)이 출시되었습니다.\n지금 업데이트하시겠습니까?',
            style: const TextStyle(fontSize: 15),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('나중에'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              child: const Text('지금 업데이트'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        );
      },
    );

    if (result != true || !context.mounted) return;

    // 업데이트 다운로드 및 설치 진행
    await downloadAndInstallApk(context);
  }

  static Future<void> downloadAndInstallApk(BuildContext context) async {
    final updateUrl = UpdateSyncManager.updateUrl;
    if (updateUrl.isEmpty) {
      final releaseUri = Uri.parse(UpdateSyncManager.releasePageUrl);
      if (await canLaunchUrl(releaseUri)) {
        await launchUrl(releaseUri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    showToast(
      level: ToastLevel.check,
      message: '최신 버전을 다운로드하고 있습니다...',
    );

    try {
      final response = await http.get(updateUrl);
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final fileName = updateUrl.split('/').last.split('?').first;
        final finalName = fileName.endsWith('.apk') ? fileName : 'violet-update.apk';
        final targetFile = File('${tempDir.path}/$finalName');

        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        await targetFile.writeAsBytes(response.bodyBytes);

        final openResult = await OpenFile.open(targetFile.path);
        if (openResult.type != ResultType.done) {
          // OpenFile 실패 시 브라우저 릴리스 페이지로 이동
          final releaseUri = Uri.parse(UpdateSyncManager.releasePageUrl);
          if (await canLaunchUrl(releaseUri)) {
            await launchUrl(releaseUri, mode: LaunchMode.externalApplication);
          }
        }
      } else {
        throw Exception('Download failed with status ${response.statusCode}');
      }
    } catch (_) {
      // 다운로드 실패 시 브라우저 페이지로 안내
      final releaseUri = Uri.parse(UpdateSyncManager.releasePageUrl);
      if (await canLaunchUrl(releaseUri)) {
        await launchUrl(releaseUri, mode: LaunchMode.externalApplication);
      }
    }
  }
}
