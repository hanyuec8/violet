// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:violet/component/hentai.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/component/image_provider.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/database/user/record.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/model/article_info.dart';
import 'package:violet/pages/article_info/article_info_page.dart';
import 'package:violet/pages/viewer/viewer_page.dart';
import 'package:violet/pages/viewer/viewer_page_provider.dart';
import 'package:violet/server/violet_v2.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/widgets/article_item/image_provider_manager.dart';

const String heroKey = 'articleInfoHero';

// TODO: expand using optional arguments
Future showArticleInfoById(BuildContext context, int id) async {
  final search = await HentaiManager.idSearch(id.toString());
  if (search.results.isEmpty) {
    return;
  }

  if (!context.mounted) return;
  showArticleInfoRaw(context: context, queryResult: search.results.first);
}

Future showArticleInfoRaw({
  required BuildContext context,
  required QueryResult queryResult,
  List<QueryResult>? usableTabList,
  bool lockRead = false,
}) async {
  final id = queryResult.id();
  final hasNoValidQuery =
      queryResult.result.keys.length == 1 &&
      queryResult.result.keys.lastOrNull == 'Id';

  if (hasNoValidQuery) {
    queryResult = await HentaiManager.idQueryWeb('$id');
  } else if (queryResult.result['source'] == 'pupil' ||
      queryResult.result['source'] == 'pupil_only' ||
      queryResult.result['ExistOnHitomi'] == 1 ||
      queryResult.groups() == null ||
      queryResult.groups() == 'N/A') {
    try {
      final gallery = await HentaiManager.tryFetchHitomiGalleryInfo(id);
      if (gallery.isNotEmpty) {
        if (gallery['Groups'] != null && (gallery['Groups'] as List).isNotEmpty) {
          queryResult.result['Groups'] = '|${(gallery['Groups'] as List).join('|')}|';
        }
        if (gallery['Characters'] != null && (gallery['Characters'] as List).isNotEmpty) {
          queryResult.result['Characters'] = '|${(gallery['Characters'] as List).join('|')}|';
        }
        if (gallery['Files'] != null) {
          queryResult.result['Files'] = gallery['Files'];
        }
        if (gallery['Artists'] != null && (gallery['Artists'] as List).isNotEmpty) {
          final currentArtists = queryResult.artists();
          if (currentArtists == null || currentArtists == 'N/A' || currentArtists == '') {
            queryResult.result['Artists'] = '|${(gallery['Artists'] as List).join('|')}|';
          }
        }
        if (gallery['Published'] != null &&
            (queryResult.published() == null ||
                queryResult.published() == '' ||
                queryResult.published() == 0)) {
          queryResult.result['Published'] = gallery['Published'];
        }
        if (gallery['Tags'] != null && (gallery['Tags'] as List).isNotEmpty) {
          final currentTags = queryResult.tags();
          if (currentTags == null || currentTags == 'N/A' || currentTags == '') {
            queryResult.result['Tags'] = '|${(gallery['Tags'] as List).join('|')}|';
          }
        }
        if (gallery['Series'] != null && (gallery['Series'] as List).isNotEmpty) {
          final currentSeries = queryResult.series();
          if (currentSeries == null || currentSeries == 'N/A' || currentSeries == '') {
            queryResult.result['Series'] = '|${(gallery['Series'] as List).join('|')}|';
          }
        }
        HybridLoader.cacheMetadata(queryResult);
      }
    } catch (_) {}
  }

  final provider = await getImageProvider(queryResult);
  final thumbnail = await provider.getThumbnailUrl();
  final headers = await provider.getHeader(0);

  final isBookmarked = await (await Bookmark.getInstance()).isBookmark(
    queryResult.id(),
  );

  if (!context.mounted) return;
  final height = MediaQuery.of(context).size.height;

  var defaultShowHeight = 400;
  if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    defaultShowHeight = (height * 0.85).toInt();
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: defaultShowHeight / height,
        minChildSize: 400 / height,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) {
          return Provider<ArticleInfo>.value(
            value: ArticleInfo.fromArticleInfo(
              queryResult: queryResult,
              thumbnail: thumbnail,
              headers: headers,
              heroKey: heroKey,
              isBookmarked: isBookmarked,
              controller: controller,
              usableTabList: usableTabList,
              lockRead: lockRead,
            ),
            child: const ArticleInfoPage(),
          );
        },
      );
    },
  );
}

Future<VioletImageProvider> getImageProviderFromId(int id) async {
  if (ProviderManager.isExists(id)) {
    return await ProviderManager.get(id);
  }

  final query = (await HentaiManager.idSearch(id.toString())).results;
  return getImageProvider(query[0]);
}

Future<VioletImageProvider> getImageProvider(QueryResult queryResult) async {
  final id = queryResult.id();
  if (ProviderManager.isExists(id)) {
    return await ProviderManager.get(id);
  }

  final provider = await HentaiManager.getImageProvider(queryResult);
  await provider.init();
  ProviderManager.insert(id, provider);

  return provider;
}

Future<void> showViewer(BuildContext context, int articleId, int page) async {
  if (Settings.useVioletServer.value) {
    Future.delayed(const Duration(milliseconds: 100)).then((value) async {
      await VioletServerV2.view(articleId);
    });
  }

  await (await User.getInstance()).insertUserLog(articleId, 0);

  var prov = await ProviderManager.get(articleId);

  await prov.init();

  var headers = await prov.getHeader(0);

  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) {
        return Provider<ViewerPageProvider>.value(
          value: ViewerPageProvider(
            uris: List<String>.filled(prov.length(), ''),
            useProvider: true,
            provider: prov,
            headers: headers,
            id: articleId,
            title: '<No Query>',
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

Future<void> showArticleInfoNotFound(
  BuildContext context,
  int id, {
  String? title,
}) async {
  if (!context.mounted) return;

  final height = MediaQuery.of(context).size.height;

  var defaultShowHeight = 400;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    defaultShowHeight = (height * 0.85).toInt();
  }

  final fallbackQueryResult = QueryResult(
    result: {
      'Id': id,
      'Title': title ?? Translations.instance!.trans('articlenotfound'),
      'Artists': '',
      'Characters': '',
      'Groups': '',
      'Language': null,
      'Series': '',
      'Tags': '',
      'Uploader': '',
      'Class': '',
      'Type': '',
      'EHash': null,
      'PublishedEH': null,
      'Files': null,
      'Thumbnail': null,
      'URL': '',
    },
  );

  final isBookmarked = await (await Bookmark.getInstance()).isBookmark(id);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: defaultShowHeight / height,
        minChildSize: 400 / height,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) {
          return Provider<ArticleInfo>.value(
            value: ArticleInfo.fromArticleInfo(
              queryResult: fallbackQueryResult,
              thumbnail: null,
              headers: null,
              heroKey: heroKey,
              isBookmarked: isBookmarked,
              controller: controller,
              lockRead: true,
            ),
            child: const ArticleInfoPage(),
          );
        },
      );
    },
  );
}
