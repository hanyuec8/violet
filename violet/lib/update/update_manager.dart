// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/network/wrapper.dart' as http;
import 'package:violet/other/dialogs.dart';
import 'package:violet/platform/android_external_storage_directory.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/version/update_sync.dart';

class UpdateManager {
  static Future<void> updateCheck(BuildContext context) async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    await UpdateSyncManager.checkUpdateSync();

    // Update is only available for Android.
    if (Platform.isAndroid) {
      if (!context.mounted) return;
      updateCheckAndDownload(context);
    }
  }

  static void updateCheckAndDownload(BuildContext context) {
    bool updateContinued = false;
    Future.delayed(const Duration(milliseconds: 100))
        .then((value) async {
          if (UpdateSyncManager.updateRequire) {
            var bb = await showYesNoDialog(
              context,
              '${Translations.instance!.trans('newupdate')} ${UpdateSyncManager.updateMessage} ${Translations.instance!.trans('wouldyouupdate')}',
            );
            if (bb == false) return;
          } else {
            return;
          }

          if (!await Permission.manageExternalStorage.isGranted) {
            if (await Permission.manageExternalStorage.request() ==
                PermissionStatus.denied) {
              if (!context.mounted) return;
              await showOkDialog(
                context,
                'If you do not allow file permissions, you cannot continue :(',
              );
              return;
            }
          }
          updateContinued = true;

          final ext = await AndroidExternalStorageDirectory.instance
              .getExternalStorageDownloadsDirectory();

          final fileName = UpdateSyncManager.updateUrl.split('/').last;
          final targetFile = File('$ext/$fileName');

          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          final response = await http.get(UpdateSyncManager.updateUrl);
          if (response.statusCode == 200) {
            await targetFile.writeAsBytes(response.bodyBytes);
            await OpenFile.open(targetFile.path);
          }
        })
        .then((value) async {
          if (updateContinued) return;

          final prefs = await SharedPreferences.getInstance();
          if (prefs.getBool('usevioletserver_check') != null) return;

          if (!context.mounted) return;
          final bb = await showYesNoDialog(
            context,
            Translations.instance!.trans('violetservermsg'),
          );
          if (bb == false) {
            await prefs.setBool('usevioletserver_check', false);
            return;
          }

          await Settings.useVioletServer.setValue(true);
          await prefs.setBool('usevioletserver_check', false);
        });
  }
}
