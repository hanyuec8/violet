// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:violet/component/hentai.dart';
import 'package:violet/component/image_provider.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/model/article_info.dart';
import 'package:violet/pages/article_info/article_info_page.dart';
import 'package:violet/widgets/article_item/image_provider_manager.dart';

// TODO: expand using optional arguments
Future showArticleInfoById(BuildContext context, int id) async {
  final search = await HentaiManager.idSearch(id.toString());
  if (search.results.isEmpty) {
    return;
  }

  if (!context.mounted) return;
  showArticleInfoRaw(
    context: context,
    queryResult: search.results.first,
  );
}

Future showArticleInfoRaw({
  required BuildContext context,
  required QueryResult queryResult,
  List<QueryResult>? usableTabList,
  bool lockRead = false,
}) async {
  final id = queryResult.id();
  final hasNoValidQuery = queryResult.result.keys.length == 1 &&
      queryResult.result.keys.lastOrNull == 'Id';

  if (hasNoValidQuery) {
    queryResult = await HentaiManager.idQueryWeb('$id');
  }

  late final VioletImageProvider provider;
  if (ProviderManager.isExists(id)) {
    provider = await ProviderManager.get(id);
  } else {
    provider = await HentaiManager.getImageProvider(queryResult);
    await provider.init();
    ProviderManager.insert(id, provider);
  }

  final thumbnail = await provider.getThumbnailUrl();
  final headers = await provider.getHeader(0);

  final isBookmarked =
      await (await Bookmark.getInstance()).isBookmark(queryResult.id());

  if (!context.mounted) return;
  final height = MediaQuery.of(context).size.height;
  // https://github.com/flutter/flutter/issues/67219
  Provider<ArticleInfo>? cache;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 400 / height,
        minChildSize: 400 / height,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) {
          cache ??= Provider<ArticleInfo>.value(
            value: ArticleInfo.fromArticleInfo(
              queryResult: queryResult,
              thumbnail: thumbnail,
              headers: headers,
              heroKey: 'zxcvzxcvzxcv',
              isBookmarked: isBookmarked,
              controller: controller,
              usableTabList: usableTabList,
              lockRead: lockRead,
            ),
            child: const ArticleInfoPage(
              key: ObjectKey('asdfasdf'),
            ),
          );
          return cache!;
        },
      );
    },
  );
}
