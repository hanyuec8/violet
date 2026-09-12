// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:math';

import 'package:auto_animated/auto_animated.dart';
import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:violet/component/hitomi/related.dart';
import 'package:violet/database/query.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/model/article_list_item.dart';
import 'package:violet/pages/article_info/tag_info_area.dart';
import 'package:violet/pages/artist_info/article_list_page.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/widgets/article_item/article_list_item_widget.dart';

class RelatedSection extends StatelessWidget {
  final int articleId;
  const RelatedSection({super.key, required this.articleId});

  @override
  Widget build(BuildContext context) {
    if (Related.isLoaded) {
      if (!Related.existsRelated(articleId)) {
        return const SizedBox.shrink();
      }
      return _buildPanel(context, Related.getRelated(articleId));
    }

    return FutureBuilder(
      future: Related.ensureLoaded(),
      builder: (context, snapshot) {
        if (!Related.isLoaded || !Related.existsRelated(articleId)) {
          return const SizedBox.shrink();
        }
        return _buildPanel(context, Related.getRelated(articleId));
      },
    );
  }

  Widget _buildPanel(BuildContext context, List<int> relatedIds) {
    return Column(
      children: [
        const DividerWidget(),
        ExpandableNotifier(
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
                  animationDuration: const Duration(
                    milliseconds: 500,
                  ),
                ),
                header: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
                  child: Text(
                    '${Translations.instance!.trans('related')} ${Translations.instance!.trans('articles')}',
                  ),
                ),
                expanded: _RelatedArea(relatedIds: relatedIds),
                collapsed: Container(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RelatedArea extends StatelessWidget {
  final List<int> relatedIds;
  const _RelatedArea({required this.relatedIds});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: QueryManager.queryIds(relatedIds),
      builder: (context, AsyncSnapshot<List<QueryResult>> snapshot) {
        if (!snapshot.hasData) return Container();

        return Column(
          children: <Widget>[
            articleArea(context, snapshot.data!),
            Visibility(
              visible: relatedIds.length > 6,
              child: more(
                context,
                () => ArticleListPage(
                  cc: snapshot.data!,
                  name:
                      '${Translations.instance!.trans('related')} ${Translations.instance!.trans('articles')}',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget more(BuildContext context, Widget Function() what) {
    return SizedBox(
      height: 60,
      child: InkWell(
        onTap: () async {
          PlatformNavigator.navigateSlide(context, what(), opaque: true);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [Text(Translations.instance!.trans('more'))],
        ),
      ),
    );
  }

  Widget articleArea(BuildContext context, List<QueryResult> cc) {
    var windowWidth = MediaQuery.of(context).size.width;
    return LiveGrid(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      showItemInterval: const Duration(milliseconds: 50),
      showItemDuration: const Duration(milliseconds: 150),
      visibleFraction: 0.001,
      itemCount: min(cc.length, 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3 / 4,
      ),
      itemBuilder: (context, index, animation) {
        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(animation),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.1),
              end: Offset.zero,
            ).animate(animation),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  child: Provider<ArticleListItem>.value(
                    value: ArticleListItem.fromArticleListItem(
                      queryResult: cc[index],
                      showDetail: false,
                      addBottomPadding: false,
                      width: (windowWidth - 4.0) / 3,
                      thumbnailTag: const Uuid().v4(),
                      usableTabList: cc,
                    ),
                    child: const ArticleListItemWidget(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
