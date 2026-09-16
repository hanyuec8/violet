// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_pickers/country.dart';
import 'package:country_pickers/country_pickers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:mdi/mdi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:violet/component/index.dart';
import 'package:violet/database/database.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/log/log.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/other/ex_country.dart';
import 'package:violet/pages/common/toast.dart';
import 'package:violet/pages/community/user_status_card.dart';
import 'package:violet/pages/database_download/database_download_page.dart';
import 'package:violet/pages/statistics/statistics_page.dart';
import 'package:violet/pages/settings/patchnote_page.dart';
import 'package:violet/pages/segment/double_tap_to_top.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/pages/settings/db_rebuild_page.dart';
import 'package:violet/pages/settings/lock_setting_page.dart';
import 'package:violet/pages/settings/log_page.dart';
import 'package:violet/pages/settings/login/ehentai_login.dart';
import 'package:violet/pages/settings/route.dart';
import 'package:violet/pages/settings/version_page.dart';
import 'package:violet/pages/settings/groups/bookmark_group.dart';
import 'package:violet/pages/settings/groups/search_group.dart';
import 'package:violet/pages/settings/settings_widgets.dart';
import 'package:violet/pages/splash/splash_page.dart';
import 'package:violet/platform/misc.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/util/helper.dart';
import 'package:violet/version/sync.dart';
import 'package:violet/version/update_sync.dart';
import 'package:violet/widgets/theme_switchable_state.dart';
import 'package:violet/network/wrapper.dart' as http;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ThemeSwitchableState<SettingsPage>
    with AutomaticKeepAliveClientMixin<SettingsPage>, DoubleTapToTopMixin {
  @override
  VoidCallback? get shouldReloadCallback =>
      () => _shouldReload = true;

  List<Widget>? _cachedGroups;
  bool _shouldReload = false;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    if (_cachedGroups == null || _shouldReload) {
      _shouldReload = false;
      _cachedGroups = <Widget>[const UserStatusCard()]
        ..addAll(buildSearchGroup(context, () => setState(() => _shouldReload = true)))
        ..addAll(_systemGroup())
        ..addAll(_securityGroup())
        ..addAll(_databaseGroup())
        ..addAll(_networkingGroup())
        ..addAll(buildBookmarkGroup(context, () => setState(() => _shouldReload = true)))
        ..addAll(_componetGroup())
        ..addAll(_viewGroup())
        ..addAll(_updateGroup())
        ..add(_bottomInfo());
    }

    return SingleChildScrollView(
      padding: EdgeInsets.only(top: statusBarHeight),
      physics: const BouncingScrollPhysics(),
      controller: doubleTapToTopScrollController = ScrollController(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: _cachedGroups!,
      ),
    );
  }

  Widget _buildItems(List<Widget> items) => buildSettingItems(items);

  @override
  bool get wantKeepAlive => true;

  List<Widget> _systemGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('system')),
      _buildItems([
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0),
              topRight: Radius.circular(8.0),
            ),
          ),
          child: ListTile(
            leading: Icon(Icons.receipt, color: Settings.majorColor.value),
            title: Text(Translations.instance!.trans('logrecord')),
            trailing: const Icon(Icons.keyboard_arrow_right),
          ),
          onTap: () {
            PlatformNavigator.navigateSlide(context, const LogPage());
          },
        ),
        ListTile(
          leading: Icon(Icons.language, color: Settings.majorColor.value),
          title: Text(Translations.instance!.trans('language')),
          trailing: const Icon(Icons.keyboard_arrow_right),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => Theme(
                data: Theme.of(context).copyWith(primaryColor: Colors.pink),
                child: CountryPickerDialog(
                  titlePadding: const EdgeInsets.symmetric(vertical: 16),
                  // searchCursorColor: Colors.pinkAccent,
                  // searchInputDecoration:
                  //     InputDecoration(hintText: 'Search...'),
                  // isSearchable: true,
                  title: const Text('Select Language'),
                  onValuePicked: (Country country) async {
                    var exc = country as ExCountry;
                    await Translations.instance!.load(exc.toString());
                    await Settings.language.setValue(exc.toString());
                    setState(() {
                      _shouldReload = true;
                    });
                  },
                  itemFilter: (c) => [].contains(c.isoCode),
                  priorityList: [
                    ExCountry.create('US'),
                    ExCountry.create('KR'),
                    ExCountry.create('JP'),
                    ExCountry.create('CN', script: 'Hant'),
                    ExCountry.create('CN', script: 'Hans'),
                    ExCountry.create('IT'),
                    ExCountry.create('ES'),
                    ExCountry.create('BR'),
                    // CountryPickerUtils.getCountryByIsoCode('RU'),
                  ],
                  itemBuilder: (Country country) {
                    return Row(
                      children: <Widget>[
                        CountryPickerUtils.getDefaultFlagImage(country),
                        const SizedBox(width: 8.0, height: 30),
                        Text((country as ExCountry).getDisplayLanguage()),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (Settings.language.value == 'ko')
          ListTile(
            leading: Icon(Icons.translate, color: Settings.majorColor.value),
            title: Text(Translations.instance!.trans('translatetagtokorean')),
            trailing: Switch(
              value: Settings.translateTags.value,
              onChanged: (newValue) async {
                await Settings.translateTags.setValue(newValue);
                setState(() {
                  _shouldReload = true;
                });
              },
              activeTrackColor: Settings.majorColor.value,
              activeColor: Settings.majorAccentColor.value,
            ),
            onTap: () async {
              await Settings.translateTags.setValue(
                !Settings.translateTags.value,
              );
              setState(() {
                _shouldReload = true;
              });
            },
          ),
        ListTile(
          leading: Icon(
            MdiIcons.imageSizeSelectLarge,
            color: Settings.majorColor.value,
          ),
          title: Text(Translations.instance!.trans('lowresmode')),
          trailing: Switch(
            value: Settings.useLowPerf.value,
            onChanged: (newValue) async {
              await Settings.useLowPerf.setValue(newValue);
              setState(() {
                _shouldReload = true;
              });
            },
            activeTrackColor: Settings.majorColor.value,
            activeColor: Settings.majorAccentColor.value,
          ),
          onTap: () async {
            await Settings.useLowPerf.setValue(!Settings.useLowPerf.value);
            setState(() {
              _shouldReload = true;
            });
          },
        ),
        ListTile(
          leading: Icon(Mdi.tableArrowRight, color: Settings.majorColor.value),
          title: Text(Translations.instance!.trans('exportlog')),
          trailing: const Icon(Icons.keyboard_arrow_right),
          onTap: () async {
            try {
              final logfile = await Logger.getExportLogFile();

              if (!await logfile.exists() || await logfile.length() == 0) {
                showToast(
                  level: ToastLevel.error,
                  message: '내보낼 로그 파일이 비어있습니다.',
                );
                return;
              }

              if (Platform.isAndroid) {
                await PlatformMiscMethods.instance.exportFile(
                  logfile.path,
                  mimeType: 'text/plain',
                  fileNameToSaveAs: 'log.txt',
                );
              } else {
                final selectedPath = await FilePicker.platform.getDirectoryPath();

                if (selectedPath == null) {
                  return;
                }

                final extpath = '$selectedPath/log.txt';
                await logfile.copy(extpath);
              }

              showToast(
                level: ToastLevel.check,
                message: Translations.instance!.trans('complete'),
              );
            } catch (e) {
              showToast(
                level: ToastLevel.error,
                message: '로그 내보내기 실패: $e',
              );
            }
          },
        ),
        ListTile(
          leading: Icon(Icons.info_outline, color: Settings.majorColor.value),
          title: Text(Translations.instance!.trans('info')),
          trailing: const Icon(Icons.keyboard_arrow_right),
          onTap: () async {
            await showDialog(
              context: context,
              builder: (BuildContext context) {
                return const VersionViewPage();
              },
            );
          },
        ),
        ListTile(
          leading: const Icon(MdiIcons.fileSign, color: Colors.cyan),
          title: Text(Translations.instance!.trans('patchnote')),
          trailing: const Icon(Icons.keyboard_arrow_right),
          onTap: () async {
            PlatformNavigator.navigateSlide(context, const PatchNotePage());
          },
        ),
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(8.0),
              bottomRight: Radius.circular(8.0),
            ),
          ),
          child: const ListTile(
            leading: Icon(MdiIcons.chartBar, color: Colors.lime),
            title: Text('통계'),
            trailing: Icon(Icons.keyboard_arrow_right),
          ),
          onTap: () async {
            PlatformNavigator.navigateSlide(context, const StatisticsPage());
          },
        ),
      ]),
    ];
  }

  List<Widget> _securityGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('security')),
      _buildItems([
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0),
              topRight: Radius.circular(8.0),
            ),
          ),
          child: ListTile(
            // borderRadius: BorderRadius.circular(8.0),
            leading: Icon(Icons.lock_outline, color: Settings.majorColor.value),
            title: Text(Translations.instance!.trans('lockapp')),
            trailing: const Icon(
              // Icons.message,
              Icons.keyboard_arrow_right,
            ),
          ),
          onTap: () async {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (context) => const LockSettingPage()),
            );
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
              MdiIcons.shieldLockOutline,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('securemode')),
            trailing: Switch(
              value: Settings.useSecureMode.value,
              onChanged: (newValue) async {
                await Settings.useSecureMode.setValue(newValue);
                await Settings.setSecureMode();
                setState(() {
                  _shouldReload = true;
                });
              },
              activeTrackColor: Settings.majorColor.value,
              activeColor: Settings.majorAccentColor.value,
            ),
          ),
          onTap: () async {
            await Settings.useSecureMode.setValue(
              !Settings.useSecureMode.value,
            );
            await Settings.setSecureMode();
            setState(() {
              _shouldReload = true;
            });
          },
        ),
      ]),
    ];
  }

  List<Widget> _databaseGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('database')),
      _buildItems([
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0),
              topRight: Radius.circular(8.0),
            ),
          ),
          onTap: () async {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const SplashPage(switching: true),
              ),
            );
          },
          child: ListTile(
            leading: Icon(
              MdiIcons.swapHorizontal,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('switching')),
            trailing: const Icon(Icons.keyboard_arrow_right),
          ),
        ),
        InkWell(
          child: ListTile(
            leading: Icon(
              MdiIcons.databaseEdit,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('dbrebuild')),
            trailing: const Icon(Icons.keyboard_arrow_right),
          ),
          onTap: () async {
            if (await showYesNoDialog(
              context,
              Translations.instance!.trans('dbrebuildmsg'),
              Translations.instance!.trans('dbrebuild'),
            )) {
              await showDialog(
                context: context,
                builder: (BuildContext context) => const DBRebuildPage(),
              );

              showToast(
                level: ToastLevel.check,
                message:
                    '${Translations.instance!.trans('dbrebuild')} ${Translations.instance!.trans('complete')}',
              );
            }
          },
        ),
        InkWell(
          child: ListTile(
            leading: Icon(
              MdiIcons.vectorIntersection,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('dbopt')),
            trailing: Switch(
              value: Settings.useOptimizeDatabase.value,
              onChanged: (newValue) async {
                await Settings.useOptimizeDatabase.setValue(newValue);
                setState(() {
                  _shouldReload = true;
                });
              },
              activeTrackColor: Settings.majorColor.value,
              activeColor: Settings.majorAccentColor.value,
            ),
          ),
          onTap: () async {
            await Settings.useOptimizeDatabase.setValue(
              !Settings.useOptimizeDatabase.value,
            );
            setState(() {
              _shouldReload = true;
            });
          },
        ),
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(8.0),
              bottomRight: Radius.circular(8.0),
            ),
          ),
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            var latestDB = SyncManager.getLatestDB().getDateTime();
            var lastDB = prefs.getString('databasesync');

            if (lastDB != null &&
                latestDB.difference(DateTime.parse(lastDB)).inHours < 1) {
              showToast(
                level: ToastLevel.check,
                message: Translations.instance!.trans('thisislatestbookmark'),
              );
              return;
            }

            var dir = await getApplicationDocumentsDirectory();
            try {
              await ((await openDatabase('${dir.path}/data/data.db')).close());
              await deleteDatabase('${dir.path}/data/data.db');
              if (Platform.isAndroid || Platform.isIOS) {
                if (await Directory('${dir.path}/data').exists()) {
                  await Directory('${dir.path}/data').delete(recursive: true);
                }
              }
            } catch (_) {}

            var targetDbType = Settings.databaseType.value;
            if (targetDbType == 'dummy') {
              targetDbType = 'global';
              await Settings.databaseType.setValue(targetDbType);
            }

            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (context) => DataBaseDownloadPage(
                      dbType: targetDbType,
                      isSync: true,
                    ),
                  ),
                )
                .then((value) async {
                  HentaiIndex.init();
                  final directory = await getApplicationDocumentsDirectory();
                  final path = File('${directory.path}/data/index.json');
                  final text = path.readAsStringSync();
                  HentaiIndex.tagCount = jsonDecode(text);
                  await DataBaseManager.reloadInstance();

                  showToast(
                    level: ToastLevel.check,
                    message: Translations.instance!.trans('synccomplete'),
                  );
                });
          },
          child: ListTile(
            leading: Icon(
              MdiIcons.databaseSync,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('syncmanual')),
            trailing: const Icon(Icons.keyboard_arrow_right),
          ),
        ),
      ]),
    ];
  }

  List<Widget> _networkingGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('network')),
      _buildItems([
        // InkWell(
        //   customBorder: const RoundedRectangleBorder(
        //       borderRadius: BorderRadius.only(
        //           topLeft: Radius.circular(8.0),
        //           topRight: Radius.circular(8.0))),
        //   child: ListTile(
        //     leading: Icon(MdiIcons.vpn, color: Settings.majorColor.value),
        //     title: const Text('VPN'),
        //     trailing: const Icon(Icons.keyboard_arrow_right),
        //   ),
        //   onTap: () {},
        // ),
        //
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0),
              topRight: Radius.circular(8.0),
            ),
          ),
          child: ListTile(
            leading: Icon(Icons.router, color: Settings.majorColor.value),
            title: Text(Translations.instance!.trans('routing_rule')),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () async {
              await showDialog(
                context: context,
                builder: (BuildContext context) => const RouteDialog(),
              );
            },
          ),
          onTap: () async {
            await showDialog(
              context: context,
              builder: (BuildContext context) => const RouteDialog(),
            );
          },
        ),

        ListTile(
          leading: Icon(Icons.router, color: Settings.majorColor.value),
          title: Text('Image ${Translations.instance!.trans('routing_rule')}'),
          trailing: const Icon(Icons.keyboard_arrow_right),
          onTap: () async {
            await showDialog(
              context: context,
              builder: (BuildContext context) => const ImageRouteDialog(),
            );
          },
        ),

        ListTile(
          leading: Icon(
            MdiIcons.commentSearch,
            color: Settings.majorColor.value,
          ),
          title: Text(Translations.instance!.trans('messagesearchapi')),
          trailing: const Icon(Icons.keyboard_arrow_right),
          onTap: () async {
            TextEditingController text = TextEditingController(
              text: Settings.searchMessageAPI.value,
            );
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
            Widget defaultButton = TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Settings.majorColor.value,
              ),
              child: Text(Translations.instance!.trans('default')),
              onPressed: () {
                _shouldReload = true;
                setState(() => text.text = 'https://koromo.cc/api/search/msg');
              },
            );
            var dialog = await showDialog(
              useRootNavigator: false,
              context: context,
              builder: (BuildContext context) => AlertDialog(
                contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                title: const Text('대사 검색기 API'),
                content: TextField(
                  controller: text,
                  autofocus: true,
                  maxLines: 3,
                ),
                actions: [defaultButton, okButton, cancelButton],
              ),
            );
            if (dialog != null && dialog == true) {
              await Settings.searchMessageAPI.setValue(text.text);
            }
          },
        ),
        ListTile(
          leading: Icon(MdiIcons.timerOff, color: Settings.majorColor.value),
          title: Text(Translations.instance!.trans('ignoretimeout')),
          trailing: Switch(
            value: Settings.ignoreTimeout.value,
            onChanged: (newValue) async {
              await Settings.ignoreTimeout.setValue(newValue);
              setState(() {
                _shouldReload = true;
              });
            },
            activeTrackColor: Settings.majorColor.value,
            activeColor: Settings.majorAccentColor.value,
          ),
        ),
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(8.0),
              bottomRight: Radius.circular(8.0),
            ),
          ),
          child: ListTile(
            leading: Image.asset(
              'assets/images/logo.png',
              width: 25,
              height: 25,
            ),
            title: Text(Translations.instance!.trans('usevioletserver')),
            trailing: Switch(
              value: Settings.useVioletServer.value,
              onChanged: (newValue) async {
                await Settings.useVioletServer.setValue(newValue);
                setState(() {
                  _shouldReload = true;
                });
              },
              activeTrackColor: Settings.majorColor.value,
              activeColor: Settings.majorAccentColor.value,
            ),
          ),
          onTap: () async {
            await Settings.useVioletServer.setValue(
              !Settings.useVioletServer.value,
            );
            setState(() {
              _shouldReload = true;
            });
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
            leading: Icon(MdiIcons.server, color: Settings.majorColor.value),
            title: Text(Translations.instance!.trans('usechunksync')),
            trailing: Switch(
              value: Settings.useChunkSync.value,
              onChanged: (newValue) async {
                await Settings.useChunkSync.setValue(newValue);
                setState(() {
                  _shouldReload = true;
                });
              },
              activeTrackColor: Settings.majorColor.value,
              activeColor: Settings.majorAccentColor.value,
            ),
          ),
          onTap: () async {
            await Settings.useChunkSync.setValue(!Settings.useChunkSync.value);
            setState(() {
              _shouldReload = true;
            });
          },
        ),
      ]),
    ];
  }
  List<Widget> _componetGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('component')),
      _buildItems([
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
          ),
          child: ListTile(
            leading: CachedNetworkImage(
              imageUrl: 'https://e-hentai.org/favicon.ico',
              width: 25,
            ),
            title: const Text('E-Hentai/ExHentai'),
            trailing: const Icon(Icons.keyboard_arrow_right),
          ),
          onTap: () async {
            var useExHentai = true;
            var dialog = await showDialog(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('E-Hentai Login'),
                contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Settings.majorColor.value,
                      ),
                      child: const Text('Login From WebPage'),
                      onPressed: () => Navigator.pop(context, 1),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Settings.majorColor.value,
                      ),
                      child: const Text('Enter Cookie Information'),
                      onPressed: () => Navigator.pop(context, 2),
                    ),
                  ],
                ),
              ),
            );

            if (dialog == null) return;

            final prefs = await SharedPreferences.getInstance();
            if (dialog == 1) {
              var cookie = await Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );

              if (cookie != null) {
                await catchUnwind(() async {
                  final res = await http.get(
                    'https://exhentai.org',
                    headers: {'Cookie': cookie},
                  );

                  // sk=...; expires=Sun, 29-Dec-2024 07:02:58 GMT; Max-Age=31536000; path=/; domain=.exhentai.org
                  final setCookie = res.headers['set-cookie'];
                  if (setCookie != null && setCookie.startsWith('sk=')) {
                    cookie += ';${setCookie.split(';')[0]}';
                  }
                });

                await prefs.setString('eh_cookies', cookie);
              }

              if (cookie != null) {
                showToast(level: ToastLevel.check, message: 'Login Success!');
              }
            } else if (dialog == 2) {
              var cookie = prefs.getString('eh_cookies');

              var sController = TextEditingController(
                text: cookie != null ? parseCookies(cookie)['sk'] : '',
              );
              var imiController = TextEditingController(
                text: cookie != null
                    ? parseCookies(cookie)['ipb_member_id']
                    : '',
              );
              var iphController = TextEditingController(
                text: cookie != null
                    ? parseCookies(cookie)['ipb_pass_hash']
                    : '',
              );
              var iController = TextEditingController(
                text: cookie != null ? parseCookies(cookie)['igneous'] : '',
              );
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
              var dialog = await showDialog(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                  actions: [okButton, cancelButton],
                  title: const Text('E-Hentai Login'),
                  contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: [
                          const Text('sk: '),
                          Expanded(child: TextField(controller: sController)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('ipb_member_id: '),
                          Expanded(child: TextField(controller: imiController)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('ipb_pass_hash: '),
                          Expanded(child: TextField(controller: iphController)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('igneous: '),
                          Expanded(child: TextField(controller: iController)),
                        ],
                      ),
                    ],
                  ),
                ),
              );

              if (dialog != null && dialog == true) {
                final cookie =
                    'sk=${sController.text};ipb_member_id=${imiController.text};ipb_pass_hash=${iphController.text};igneous=${iController.text}';
                await prefs.setString('eh_cookies', cookie);
              }
            }
            final cookie = prefs.getString('eh_cookies') ?? '';
            final res = await http.get(
              'https://exhentai.org',
              headers: {'Cookie': cookie},
            );

            res.body.trim().isEmpty || useExHentai == false
                ? useExHentai = false
                : useExHentai = true;
            (res.headers['set-cookie'] ?? '').split(';')[0] ==
                        'igneous=mystery' ||
                    useExHentai == false
                ? useExHentai = false
                : useExHentai = true;

            final parsedCookie = parseCookies(cookie);
            if (parsedCookie['igneous'] == null ||
                parsedCookie['igneous'] == 'mystery' ||
                useExHentai == false) {
              useExHentai = false;
            } else {
              useExHentai = true;
            }
            if (useExHentai) {
              Settings.searchRule = 'Hitomi|ExHentai|EHentai|NHentai'.split(
                '|',
              );
              await prefs.setString(
                'searchrule',
                'Hitomi|ExHentai|EHentai|NHentai',
              );
            } else {
              Settings.searchRule = 'Hitomi|EHentai|ExHentai|NHentai'.split(
                '|',
              );
              await prefs.setString(
                'searchrule',
                'Hitomi|EHentai|ExHentai|NHentai',
              );
            }
          },
        ),
      ]),
    ];
  }

  List<Widget> _viewGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('view')),
      _buildItems([
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
          ),
          child: ListTile(
            leading: Icon(
              MdiIcons.progressClock,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('showarticleprogress')),
            trailing: Switch(
              value: Settings.showArticleProgress.value,
              onChanged: (newValue) async {
                await Settings.showArticleProgress.setValue(newValue);
                setState(() {
                  _shouldReload = true;
                });
              },
              activeTrackColor: Settings.majorColor.value,
              activeColor: Settings.majorAccentColor.value,
            ),
          ),
          onTap: () async {
            await Settings.showArticleProgress.setValue(
              !Settings.showArticleProgress.value,
            );
            setState(() {
              _shouldReload = true;
            });
          },
        ),
      ]),
    ];
  }

  List<Widget> _updateGroup() {
    return [
      SettingGroupName(name: Translations.instance!.trans('update')),
      _buildItems([
        InkWell(
          customBorder: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8.0),
              topRight: Radius.circular(8.0),
            ),
          ),
          child: ListTile(
            // borderRadius: BorderRadius.circular(8.0),
            leading: Icon(Icons.update, color: Settings.majorColor.value),
            title: Text(Translations.instance!.trans('checkupdate')),
            trailing: const Icon(
              // Icons.message,
              Icons.keyboard_arrow_right,
            ),
          ),
          onTap: () async {
            await UpdateSyncManager.checkUpdateSync();

            if (UpdateSyncManager.updateRequire) {
              showToast(
                level: ToastLevel.check,
                message: Translations.instance!.trans('newupdate'),
              );
            } else {
              showToast(
                level: ToastLevel.check,
                message: Translations.instance!.trans('latestver'),
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
              MdiIcons.cellphoneArrowDown,
              color: Settings.majorColor.value,
            ),
            title: Text(Translations.instance!.trans('manualupdate')),
            trailing: const Icon(
              // Icons.message,
              Icons.keyboard_arrow_right,
            ),
          ),
          onTap: () async {
            await UpdateSyncManager.checkUpdateSync();

            if (!UpdateSyncManager.updateRequire) {
              showToast(
                level: ToastLevel.check,
                message: Translations.instance!.trans('latestver'),
              );
              return;
            }

            if (Platform.isIOS) {
              showToast(
                level: ToastLevel.warning,
                message: Translations.instance!.trans('cannotuseios'),
              );
              return;
            }

            final url = Uri.parse(
              'https://github.com/TaYaKi71751/violet/releases/latest',
            );
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
        ),
      ]),
    ];
  }

  _bottomInfo() {
    return Container(
      margin: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: <Widget>[
            // Card(
            //   elevation: 5,
            //   shape: RoundedRectangleBorder(
            //     borderRadius: BorderRadius.circular(8.0),
            //   ),
            //   child:
            InkWell(
              child: Image.asset(
                'assets/images/logo.png',
                width: 100,
                height: 100,
              ),
              //onTap: () {},
            ),
            // ),
            const Padding(padding: EdgeInsets.only(top: 12)),
            Text(
              'Project Violet',
              style: TextStyle(
                color: Settings.themeWhat.value ? Colors.white : Colors.black87,
                fontSize: 16.0,
                fontFamily: 'Calibre-Semibold',
                letterSpacing: 1.0,
              ),
            ),
            Text(
              'Copyright (C) 2020-2024 by project-violet',
              style: TextStyle(
                color: Settings.themeWhat.value ? Colors.white : Colors.black87,
                fontSize: 12.0,
                fontFamily: 'Calibre-Semibold',
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

