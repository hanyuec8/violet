// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:violet/database/user/download.dart';
import 'package:violet/database/user/record.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/model/article_info.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/article_info/article_source_badge.dart';
import 'package:violet/pages/article_info/comment_area.dart';
import 'package:violet/pages/article_info/preview_area.dart';
import 'package:violet/pages/article_info/related_section.dart';
import 'package:violet/pages/article_info/simple_info.dart';
import 'package:violet/pages/article_info/tag_info_area.dart';
export 'package:violet/pages/article_info/tag_info_area.dart';
import 'package:violet/pages/common/toast.dart';
import 'package:violet/pages/common/utils.dart';
import 'package:violet/pages/download/download_page.dart';
import 'package:violet/pages/viewer/viewer_page.dart';
import 'package:violet/pages/viewer/viewer_page_provider.dart';
import 'package:violet/script/script_manager.dart';
import 'package:violet/server/violet_v2.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/style/palette.dart';
import 'package:violet/variables.dart';
import 'package:violet/widgets/article_item/image_provider_manager.dart';

class ArticleInfoPage extends StatelessWidget {
  const ArticleInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final data = Provider.of<ArticleInfo>(context);
    final mediaQuery = MediaQuery.of(context);

    Variables.setArticleInfoHeight(
      height - 36 - (mediaQuery.padding + mediaQuery.viewInsets).bottom,
    );

    return Container(
      color: Palette.themeColorLightShallow,
      padding: EdgeInsets.only(top: 0, bottom: Variables.bottomBarHeight),
      child: Card(
        elevation: 5,
        color: Palette.themeColorLightShallow,
        child: SizedBox(
          width: width - 16,
          height: Variables.articleInfoHeight,
          child: Container(
            color: Settings.themeWhat.value
                ? Colors.black.withOpacity(0.9)
                : Colors.white.withOpacity(0.97),
            child: ListView(
              controller: data.controller,
              children: [
                Container(
                  width: width,
                  height: simpleInfoHeight(),
                  color: Settings.themeWhat.value
                      ? Colors.grey.shade900.withOpacity(0.6)
                      : Colors.white.withOpacity(0.2),
                  child: SimpleInfoWidget(),
                ),
                buttonArea(context),
                TagInfoAreaWidget(queryResult: data.queryResult),
                const DividerWidget(),
                CommentArea(queryResult: data.queryResult),
                const DividerWidget(),
                ExpandableNotifier(
                  initialExpanded: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: ScrollOnExpand(
                      scrollOnExpand: true,
                      scrollOnCollapse: false,
                      child: ExpandablePanel(
                        theme: ExpandableThemeData(
                          iconColor: Settings.themeWhat.value
                              ? Colors.white
                              : Colors.grey,
                          animationDuration: const Duration(milliseconds: 500),
                        ),
                        header: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
                          child: Text(Translations.instance!.trans('preview')),
                        ),
                        expanded: PreviewAreaWidget(
                          queryResult: data.queryResult,
                          onPageTapped: (page) async =>
                              await readButtonEvent(context, data, page),
                        ),
                        collapsed: Container(),
                      ),
                    ),
                  ),
                ),
                RelatedSection(articleId: data.queryResult.id()),
              ],
            ),
          ),
        ),
      ),
    );
  }


  double simpleInfoHeight() {
    const bottomPadding = 16;
    final height = (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? 4 * 100.0
        : 4 * 50.0;
    return height + bottomPadding;
  }

  Column buttonArea(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final buttonWidth = (width - 32 - 64 - 32) / 2;
    final buttonHeight =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? 36.0
        : null;
    final iconSize =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
        ? 20.0
        : null;
    final data = Provider.of<ArticleInfo>(context);

    SizedBox buttonInner(IconData icon, String text) {
      return SizedBox(
        width: buttonWidth,
        height: buttonHeight,
        child: Align(
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: iconSize),
              const SizedBox(width: 6.0),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Settings.majorColor.value.withAlpha(230),
              ),
              onPressed: () async => await downloadButtonEvent(context, data),
              child: buttonInner(
                MdiIcons.download,
                Translations.instance!.trans('download'),
              ),
            ),
            const SizedBox(width: 4.0),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Settings.majorColor.value,
              ),
              onPressed: data.lockRead
                  ? null
                  : () async => await readButtonEvent(context, data),
              child: buttonInner(
                MdiIcons.bookOpenPageVariant,
                Translations.instance!.trans('read'),
              ),
            ),
          ],
        ),
        ArticleSourceBadge(data: data),
      ],
    );
  }

  downloadButtonEvent(context, data) async {
    if (Platform.isAndroid &&
        !Settings.useInnerStorage.value &&
        !await Permission.manageExternalStorage.isGranted) {
      if (await Permission.manageExternalStorage.request() ==
          PermissionStatus.denied) {
        await showOkDialog(
          context,
          'If you do not allow file permissions, you cannot continue :(',
        );
        return;
      }
    }
    if (!DownloadPageManager.downloadPageLoaded) {
      showToast(
        level: ToastLevel.warning,
        message: 'You need to open the download tab!',
      );
      return;
    }

    if ((await Download.getInstance()).isDownloadedArticle(
      data.queryResult.id(),
      false,
    )) {
      if (await showYesNoDialog(context, '이미 다운로드된 작품입니다. 그래도 다운로드할까요?') !=
          true) {
        return;
      }
    }

    showToast(
      icon: Icons.download,
      level: ToastLevel.check,
      message:
          '${data.queryResult.id()}${Translations.instance!.trans('addtodownloadqueue')}',
    );

    await ScriptManager.refresh();

    DownloadPageManager.taskFromQueryResultController!.add(data.queryResult);
    Navigator.pop(context);
  }

  readButtonEvent(BuildContext context, ArticleInfo data, [int? page]) async {
    if (Settings.useVioletServer.value) {
      Future.delayed(const Duration(milliseconds: 100)).then((value) async {
        await VioletServerV2.view(data.queryResult.id());
      });
    }
    await (await User.getInstance()).insertUserLog(data.queryResult.id(), 0);

    await ScriptManager.refresh();

    if (!ProviderManager.isExists(data.queryResult.id())) {
      return;
    }

    var prov = await ProviderManager.get(data.queryResult.id());

    await prov.init();

    dynamic navigatorFunc = Navigator.push;

    if (Settings.usingPushReplacementOnArticleRead.value) {
      navigatorFunc = Navigator.pushReplacement;
    }

    if (!context.mounted) return;
    navigatorFunc(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) {
          return Provider<ViewerPageProvider>.value(
            value: ViewerPageProvider(
              uris: List<String>.filled(prov.length(), ''),
              useProvider: true,
              provider: prov,
              headers: data.headers,
              id: data.queryResult.id(),
              title: data.queryResult.title(),
              usableTabList: data.usableTabList,
              jumpPage: page,
            ),
            child: const ViewerPage(),
          );
        },
      ),
    ).then((value) async {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    });
  }
}
