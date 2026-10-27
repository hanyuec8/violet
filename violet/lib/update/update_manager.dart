// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:violet/log/log.dart';
import 'package:violet/pages/common/toast.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/version/update_sync.dart';

class UpdateManager {
  /// 앱 내부 임시 캐시 디렉터리에 보관된 모든 APK 잔여물 완전 삭제 (무흔적 유지)
  static Future<void> clearUpdateCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return;

      final files = tempDir.listSync().whereType<File>();
      for (final file in files) {
        final path = file.path.toLowerCase();
        if (path.endsWith('.apk')) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      Logger.info('[UpdateManager] Clear cache error: $e');
    }
  }

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
              Icon(Icons.system_update, color: Settings.majorColor.value),
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
                backgroundColor: Settings.majorColor.value,
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

    // 업데이트 다운로드 및 설치 진행 (실시간 프로그레스 바 다이얼로그)
    await downloadAndInstallApk(context);
  }

  static Future<void> downloadAndInstallApk(BuildContext context) async {
    final updateUrl = UpdateSyncManager.updateUrl;
    if (updateUrl.isEmpty) {
      _openBrowserReleasePage();
      return;
    }

    // 다운로드 시작 전 이전 시도 잔여 APK 먼저 청소
    await clearUpdateCache();

    if (!context.mounted) return;

    // 실시간 다운로드 다이얼로그 표시
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _UpdateDownloadDialog(updateUrl: updateUrl);
      },
    );

    if (success != true) {
      // 사용자가 취소했거나 다운로드 실패
      return;
    }
  }

  static Future<void> _openBrowserReleasePage() async {
    final releaseUri = Uri.parse(UpdateSyncManager.releasePageUrl);
    if (await canLaunchUrl(releaseUri)) {
      await launchUrl(releaseUri, mode: LaunchMode.externalApplication);
    }
  }
}

/// 실시간 다운로드 프로그레스 바 다이얼로그 위젯
class _UpdateDownloadDialog extends StatefulWidget {
  final String updateUrl;

  const _UpdateDownloadDialog({required this.updateUrl});

  @override
  State<_UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<_UpdateDownloadDialog> {
  final CancelToken _cancelToken = CancelToken();
  double _progress = 0.0;
  String _currentMb = '0.0';
  String _totalMb = '0.0';
  String _percent = '0%';
  bool _isError = false;
  File? _downloadedFile;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel();
    }
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final finalName = 'violet_update_${UpdateSyncManager.version}.apk';
      _downloadedFile = File('${tempDir.path}/$finalName');

      if (await _downloadedFile!.exists()) {
        await _downloadedFile!.delete();
      }

      final dio = Dio();
      await dio.download(
        widget.updateUrl,
        _downloadedFile!.path,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _progress = received / total;
              _currentMb = (received / (1024 * 1024)).toStringAsFixed(1);
              _totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
              _percent = '${(_progress * 100).toInt()}%';
            });
          }
        },
      );

      if (!mounted) return;

      // 100% 완료 즉시 다이얼로그 닫고 시스템 설치 창 자동 호출
      Navigator.pop(context, true);

      final openResult = await OpenFile.open(_downloadedFile!.path);
      if (openResult.type != ResultType.done) {
        showToast(
          level: ToastLevel.warning,
          message: '패키지 설치 창을 열지 못했습니다. 브라우저로 이동합니다.',
        );
        UpdateManager._openBrowserReleasePage();
      }
    } catch (e) {
      if (_cancelToken.isCancelled) {
        // 사용자 취소 시 파일 삭제
        if (_downloadedFile != null && await _downloadedFile!.exists()) {
          try {
            await _downloadedFile!.delete();
          } catch (_) {}
        }
        return;
      }

      Logger.error('[UpdateManager] Download error: $e');
      if (mounted) {
        setState(() {
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      title: Row(
        children: [
          Icon(
            _isError ? Icons.error_outline : Icons.downloading,
            color: _isError ? Colors.redAccent : Settings.majorColor.value,
          ),
          const SizedBox(width: 8),
          Text(
            _isError ? '다운로드 실패' : '최신 버전 다운로드 중...',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: _isError
          ? const Text(
              '업데이트 파일을 다운로드하는 도중 오류가 발생했습니다.\n브라우저에서 직접 다운로드하시겠습니까?',
              style: TextStyle(fontSize: 14),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.0),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Settings.majorColor.value,
                    ),
                    minHeight: 8.0,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _progress > 0
                          ? '$_currentMb MB / $_totalMb MB'
                          : '다운로드를 준비하고 있습니다...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (_progress > 0)
                      Text(
                        _percent,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Settings.majorColor.value,
                        ),
                      ),
                  ],
                ),
              ],
            ),
      actions: <Widget>[
        if (_isError) ...[
          TextButton(
            child: const Text('닫기'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Settings.majorColor.value,
              foregroundColor: Colors.white,
            ),
            child: const Text('브라우저에서 열기'),
            onPressed: () {
              Navigator.pop(context, false);
              UpdateManager._openBrowserReleasePage();
            },
          ),
        ] else ...[
          TextButton(
            child: const Text('취소'),
            onPressed: () {
              _cancelToken.cancel('사용자 취소');
              Navigator.pop(context, false);
            },
          ),
        ],
      ],
    );
  }
}
