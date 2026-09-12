// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:violet/component/eh/eh_bookmark.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/log/log.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/common/toast.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/pages/settings/bookmark_version_select.dart';
import 'package:violet/pages/settings/import_from_eh.dart';
import 'package:violet/pages/settings/restore_bookmark.dart';
import 'package:violet/pages/settings/settings_widgets.dart';
import 'package:violet/platform/misc.dart';
import 'package:violet/server/violet.dart';
import 'package:violet/settings/settings.dart';

List<Widget> buildBookmarkGroup(BuildContext context, VoidCallback onReload) {
  return [
    SettingGroupName(name: Translations.instance!.trans('bookmark')),
    buildSettingItems([
      InkWell(
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8.0),
            topRight: Radius.circular(8.0),
          ),
        ),
        onTap: null,
        child: ListTile(
          leading: Icon(
            MdiIcons.bookArrowUpOutline,
            color: Settings.majorColor.value,
          ),
          title: Text(Translations.instance!.trans('autobackupbookmark')),
          trailing: Switch(
            value: Settings.autobackupBookmark.value,
            onChanged: null,
            activeTrackColor: Settings.majorColor.value,
            activeColor: Settings.majorAccentColor.value,
          ),
        ),
      ),
      ListTile(
        leading: Icon(
          MdiIcons.bookArrowDownOutline,
          color: Settings.majorColor.value,
        ),
        title: Text(Translations.instance!.trans('restoringbookmark')),
        trailing: const Icon(Icons.keyboard_arrow_right),
        onTap: () async {
          await showOkDialog(
            context,
            Translations.instance!.trans('restorebookmarkmsg'),
            Translations.instance!.trans('warning'),
          );

          final prefs = await SharedPreferences.getInstance();
          var myappid = prefs.getString('fa_userid');

          TextEditingController text = TextEditingController(text: myappid);
          Widget okButton = TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Settings.majorColor.value,
            ),
            child: Text(Translations.instance!.trans('ok')),
            onPressed: () {
              Navigator.pop(context, true);
            },
          );
          Widget cancelButton = TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Settings.majorColor.value,
            ),
            child: Text(Translations.instance!.trans('cancel')),
            onPressed: () {
              Navigator.pop(context, false);
            },
          );
          if (!context.mounted) return;
          var dialog = await showDialog(
            useRootNavigator: false,
            context: context,
            builder: (BuildContext context) => AlertDialog(
              contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              title: const Text('Enter User App Id'),
              content: TextField(
                controller: text,
                autofocus: true,
                maxLines: 3,
              ),
              actions: [okButton, cancelButton],
            ),
          );
          if (dialog == null || dialog == false) {
            return;
          }

          try {
            var result = await VioletServer.restoreBookmark(text.text);
            if (result == null) {
              if (!context.mounted) return;
              await showOkDialog(
                context,
                "Invalid User-App-Id! If you're still getting this error, contact the developer.",
                Translations.instance!.trans('restoringbookmark'),
              );
              return;
            }

            var versions = await VioletServer.versionsBookmark(text.text);
            if (versions == null) {
              if (!context.mounted) return;
              await showOkDialog(
                context,
                '북마크 버전 정보를 가져오는데 오류가 발생했습니다. UserAppId와 함께 개발자에게 문의하시기 바랍니다.',
                Translations.instance!.trans('restoringbookmark'),
              );
              return;
            }

            if (!context.mounted) return;
            var version = await PlatformNavigator.navigateSlide(
              context,
              BookmarkVersionSelectPage(
                userAppId: text.text,
                versions: versions,
              ),
            );

            if (version == null) {
              return;
            }

            if (!context.mounted) return;
            var restoreWithRecord = await showYesNoDialog(
              context,
              '열람기록도 같이 복원할까요?',
            );

            var bookmark = await VioletServer.resotreBookmarkWithVersion(
              text.text,
              version,
            );

            if (!context.mounted) return;
            var rr = await showDialog(
              context: context,
              builder: (BuildContext context) => RestoreBookmarkPage(
                source: bookmark,
                restoreWithRecord: restoreWithRecord,
              ),
            );

            if (rr != null && rr == false) {
              return;
            }
          } catch (e, st) {
            Logger.error(
              '[Restore Bookmark] $e\n'
              '$st',
            );
            showToast(
              level: ToastLevel.error,
              message: 'Bookmark Restoring Error!',
            );
            return;
          }

          await Bookmark.getInstance();

          showToast(
            level: ToastLevel.check,
            message: Translations.instance!.trans('importbookmark'),
          );
        },
      ),
      ListTile(
        leading: Icon(MdiIcons.import, color: Settings.majorColor.value),
        title: Text(Translations.instance!.trans('importingbookmark')),
        trailing: const Icon(Icons.keyboard_arrow_right),
        onTap: () async {
          try {
            await FilePicker.platform.clearTemporaryFiles();
            final filePickerResult = await FilePicker.platform.pickFiles();
            final pickedFilePath = filePickerResult?.files.singleOrNull?.path;

            if (pickedFilePath == null) {
              showToast(
                level: ToastLevel.error,
                message: Translations.instance!.trans('noselectedb'),
              );

              return;
            }

            final pickedFile = File(pickedFilePath);
            final db = (await getApplicationDocumentsDirectory());

            await pickedFile.copy('${db.path}/user.db');

            await Bookmark.getInstance();

            showToast(
              level: ToastLevel.check,
              message: Translations.instance!.trans('importbookmark'),
            );
          } catch (e, st) {
            Logger.error(
              '[Import Bookmark] $e\n'
              '$st',
            );
            showToast(
              level: ToastLevel.error,
              message: Translations.instance!.trans('failimportbookmark'),
            );
          }
        },
      ),
      ListTile(
        leading: Icon(MdiIcons.export, color: Settings.majorColor.value),
        title: Text(Translations.instance!.trans('exportingbookmark')),
        trailing: const Icon(Icons.keyboard_arrow_right),
        onTap: () async {
          try {
            final dir = (await getApplicationDocumentsDirectory());
            final bookmarkDatabaseFile = File('${dir.path}/user.db');

            if (Platform.isAndroid) {
              await PlatformMiscMethods.instance.exportFile(
                bookmarkDatabaseFile.path,
                mimeType: 'application/vnd.sqlite3',
                fileNameToSaveAs: 'violet-bookmarks.db',
              );
            } else if (Platform.isIOS) {
              final bytes = await bookmarkDatabaseFile.readAsBytes();

              await FlutterFileDialog.saveFile(
                params: SaveFileDialogParams(
                  data: bytes,
                  fileName: 'bookmark.db',
                ),
              );
            } else {
              final selectedPath = await FilePicker.platform
                  .getDirectoryPath();

              if (selectedPath == null) {
                return;
              }

              final extpath = '$selectedPath/bookmark.db';

              await bookmarkDatabaseFile.copy(extpath);
            }

            showToast(
              level: ToastLevel.check,
              message: Translations.instance!.trans('exportbookmark'),
            );
          } catch (e, st) {
            Logger.error(
              '[Export Bookmark] $e\n'
              '$st',
            );
            showToast(
              level: ToastLevel.error,
              message: Translations.instance!.trans('failexportbookmark'),
            );
          }
        },
      ),
      InkWell(
        child: ListTile(
          leading: Icon(
            MdiIcons.cloudSearchOutline,
            color: Settings.majorColor.value,
          ),
          title: Text(Translations.instance!.trans('importfromeh')),
          trailing: const Icon(Icons.keyboard_arrow_right),
        ),
        onTap: () async {
          final prefs = await SharedPreferences.getInstance();
          var ehc = prefs.getString('eh_cookies');

          if (ehc == null || ehc == '') {
            showToast(
              level: ToastLevel.error,
              message: Translations.instance!.trans('setcookiefirst'),
            );
            return;
          }

          if (!context.mounted) return;
          await showDialog(
            context: context,
            builder: (BuildContext context) => const ImportFromEHPage(),
          );

          if (EHBookmark.bookmarkInfo == null) {
            showToast(
              level: ToastLevel.warning,
              message: Translations.instance!.trans('bookmarkisempty'),
            );
            return;
          }

          int count = 0;
          for (var element in EHBookmark.bookmarkInfo!) {
            count += element.length;
          }

          if (!context.mounted) return;
          var qqq = await showYesNoDialog(
            context,
            Translations.instance!
                .trans('ensurecreatebookmark')
                .replaceAll('\$1', count.toString()),
          );
          if (qqq) {
            var bookmark = await Bookmark.getInstance();
            for (int i = 0; i < EHBookmark.bookmarkInfo!.length; i++) {
              if (EHBookmark.bookmarkInfo![i].isEmpty) continue;
              await bookmark.createGroup('Favorite $i', '', Colors.black);
              var group = (await bookmark.getGroup())
                  .where((element) => element.name() == 'Favorite $i')
                  .last
                  .id();
              for (int j = 0; j < EHBookmark.bookmarkInfo![i].length; j++) {
                await bookmark.insertArticle(
                  EHBookmark.bookmarkInfo![i].elementAt(j).toString(),
                  DateTime.now(),
                  group,
                );
              }
            }

            showToast(
              level: ToastLevel.check,
              message: Translations.instance!.trans('completeimportbookmark'),
            );
          }
        },
      ),
      InkWell(
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(8.0),
            bottomRight: Radius.circular(8.0),
          ),
        ),
        child: ListTile(
          leading: Icon(
            MdiIcons.cloudSearchOutline,
            color: Settings.majorColor.value,
          ),
          title: Text(Translations.instance!.trans('importfromjson')),
          trailing: const Icon(Icons.keyboard_arrow_right),
        ),
        onTap: () async {
          TextEditingController textController = TextEditingController();

          Widget importButton = TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Settings.majorColor.value,
            ),
            child: const Text('Import'),
            onPressed: () async {
              Navigator.pop(context, textController.text);
            },
          );
          Widget cancelButton = TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Settings.majorColor.value,
            ),
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.pop(context, null);
            },
          );

          final text = await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(Translations.instance!.trans('importfromjson')),
                contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                actions: [importButton, cancelButton],
                content: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  reverse: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        Translations.instance!.trans('pasteyourbookmarktext'),
                      ),
                      Row(
                        children: [
                          const Text('JSON: '),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText:
                                    'ex: ["1207894", "artist:michiking", ...]',
                              ),
                              controller: textController,
                              keyboardType: TextInputType.multiline,
                              minLines: null,
                              maxLines: null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );

          if (text == null) return;

          try {
            var json = jsonDecode(text) as List<dynamic>;
            var groupName = 'Imported at ${DateTime.now().toLocal()}';
            var bookmark = await Bookmark.getInstance();
            await bookmark.createGroup(groupName, '', Colors.black);
            var group = (await bookmark.getGroup())
                .where((element) => element.name() == groupName)
                .first
                .id();
            for (int j = 0; j < json.length; j++) {
              var tar = json.elementAt(j).toString();
              if (int.tryParse(tar) != null) {
                await bookmark.insertArticle(tar, DateTime.now(), group);
              } else if (tar.contains(':') &&
                  ['artist', 'group'].contains(tar.split(':')[0])) {
                await bookmark.bookmarkArtist(
                  tar.split(':')[1],
                  tar.split(':')[0] == 'artist'
                      ? ArtistType.artist
                      : ArtistType.group,
                  group,
                );
              }
            }

            if (!context.mounted) return;
            await showOkDialog(context, 'Success!');
          } catch (e, st) {
            Logger.error(
              '[Import from hiyobi] $e\n'
              '$st',
            );

            if (!context.mounted) return;
            await showOkDialog(
              context,
              'Bookmark format is not correct. Please refer to Log Record for details.',
            );
          }
        },
      ),
    ]),
  ];
}
