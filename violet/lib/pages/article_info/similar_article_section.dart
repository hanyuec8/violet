// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:auto_animated/auto_animated.dart';
import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:violet/component/hitomi/first_page_grouper.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/component/hitomi/related.dart';
import 'package:violet/component/index.dart';
import 'package:violet/database/query.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/model/article_list_item.dart';
import 'package:violet/pages/article_info/tag_info_area.dart';
import 'package:violet/pages/artist_info/article_list_page.dart';
import 'package:violet/pages/common/utils.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/style/palette.dart';
import 'package:violet/widgets/article_item/article_list_item_widget.dart';

class SimilarArticleSection extends StatefulWidget {
  final QueryResult queryResult;

  const SimilarArticleSection({super.key, required this.queryResult});

  @override
  State<SimilarArticleSection> createState() => _SimilarArticleSectionState();
}

class _SimilarArticleSectionState extends State<SimilarArticleSection> {
  List<QueryResult> _variants = [];
  List<QueryResult> _similarArticles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVariantsAndSimilars();
  }

  @override
  void didUpdateWidget(covariant SimilarArticleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryResult.id() != widget.queryResult.id()) {
      _loadVariantsAndSimilars();
    }
  }

  Future<void> _loadVariantsAndSimilars() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final current = widget.queryResult;

    try {
      // 1. 첫 페이지 기반 동일 작품/다국어 판본(Variants) 탐색
      final variantsFuture = FirstPageGrouper.findVariants(current);

      // 2. 그림체·유사 작가 기반 추천 탐색
      final similarsFuture = _fetchSimilarArticles(current);

      final results = await Future.wait([variantsFuture, similarsFuture]);

      if (!mounted) return;
      setState(() {
        _variants = results[0];
        _similarArticles = results[1];
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<List<QueryResult>> _fetchSimilarArticles(QueryResult current) async {
    final currentId = current.id();
    final results = <QueryResult>[];
    final seenIds = <int>{currentId};

    // 작가 추출
    final artistStr = current.artists() ?? '';
    final artists = artistStr
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'n/a')
        .toList();

    // 1단계: 동일 작가 최신작 수집 (그림체 100% 일치 - 한국어 우선)
    if (artists.isNotEmpty) {
      try {
        final artistArticles = await HybridLoader.fetchArtistArticlesHybrid(
          name: artists.first,
          type: 'artist',
          pageSize: 30,
          language: 'korean',
        );
        for (final art in artistArticles) {
          if (seenIds.add(art.id())) {
            results.add(art);
          }
        }
      } catch (_) {}
    }

    // 2단계: 동일 작가 작품이 6개 미만인 경우 유사 작가(Similar Artists) 화풍 매칭 (한국어 우선)
    if (results.length < 6 && artists.isNotEmpty) {
      try {
        final similarArtists = HentaiIndex.calculateSimilarArtists(artists.first);
        for (final (simArtist, _) in similarArtists.take(3)) {
          if (results.length >= 12) break;
          try {
            final simArticles = await HybridLoader.fetchArtistArticlesHybrid(
              name: simArtist,
              type: 'artist',
              pageSize: 6,
              language: 'korean',
            );
            for (final art in simArticles) {
              if (seenIds.add(art.id())) {
                results.add(art);
                if (results.length >= 12) break;
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    // 3단계: 작가가 없거나 여전히 부족한 경우 기존 연관 DB(related.json) 매칭
    if (results.length < 6) {
      try {
        await Related.ensureLoaded();
        if (Related.existsRelated(currentId)) {
          final relatedIds = Related.getRelated(currentId)
              .where((id) => !seenIds.contains(id))
              .take(12 - results.length)
              .toList();

          if (relatedIds.isNotEmpty) {
            // 3중 하이브리드 복원 (로컬DB -> 디스크/세션 캐시 -> 온라인 페치)
            final cachedBatch = await HybridLoader.getCachedMetadataBatch(relatedIds);
            final stillMissing = <int>[];

            for (final id in relatedIds) {
              if (cachedBatch.containsKey(id)) {
                final item = cachedBatch[id]!;
                if (seenIds.add(item.id())) {
                  results.add(item);
                }
              } else {
                stillMissing.add(id);
              }
            }

            if (stillMissing.isNotEmpty) {
              await Future.wait(
                stillMissing.take(6).map((id) async {
                  try {
                    final item = await HybridLoader.idQueryHitomiFast(id)
                        .timeout(const Duration(milliseconds: 1500));
                    if (seenIds.add(item.id())) {
                      results.add(item);
                    }
                  } catch (_) {}
                }),
              );
            }
          }
        }
      } catch (_) {}
    }

    return results;
  }

  @override
  Widget build(BuildContext context) {
    final hasVariants = _variants.length > 1;
    final showVariantsBar = Settings.groupByFirstPage.value && hasVariants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DividerWidget(),

        // 1. 다국어/판본 칩 바 (설정 ON이고 동일 작품 번역본이 2개 이상일 때 노출)
        if (showVariantsBar) _buildVariantsBar(context),

        // 2. 비슷한 작품 추천 섹션 (기본 닫힘 상태로 항상 유지)
        _buildSimilarSection(context),
      ],
    );
  }

  /// 다국어/판본 원클릭 전환 바
  Widget _buildVariantsBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.language, size: 18, color: Palette.themeColor),
              const SizedBox(width: 6),
              Text(
                '다른 언어 / 판본 (${_variants.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: _variants.map((v) {
                final isCurrent = v.id() == widget.queryResult.id();
                final langName = _getReadableLanguage(v.language()?.toString() ?? '');
                final pageCount = v.files() != null && v.files()! > 0 ? '${v.files()}p' : '';

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Material(
                    color: isCurrent
                        ? Palette.themeColor
                        : (Settings.themeWhat.value
                            ? Colors.grey.shade800
                            : Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: isCurrent
                          ? null
                          : () {
                              showArticleInfoRaw(
                                context: context,
                                queryResult: v,
                              );
                            },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isCurrent ? '$langName [현재]' : langName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent
                                    ? Colors.white
                                    : (Settings.themeWhat.value ? Colors.white70 : Colors.black87),
                              ),
                            ),
                            if (pageCount.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                pageCount,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isCurrent
                                      ? Colors.white70
                                      : (Settings.themeWhat.value ? Colors.white38 : Colors.black45),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  /// 비슷한 작품 추천 섹션 (기본 상태 닫아두기: initialExpanded: false)
  Widget _buildSimilarSection(BuildContext context) {
    final countText = _isLoading ? '...' : '${_similarArticles.length}';

    return ExpandableNotifier(
      initialExpanded: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: ScrollOnExpand(
          scrollOnExpand: true,
          scrollOnCollapse: false,
          child: ExpandablePanel(
            theme: ExpandableThemeData(
              iconColor: Settings.themeWhat.value ? Colors.white : Colors.grey,
              animationDuration: const Duration(milliseconds: 500),
            ),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 0, 0),
              child: Row(
                children: [
                  Text(
                    '${Translations.instance!.trans('related')} ${Translations.instance!.trans('articles')} ($countText)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (_isLoading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ],
                ],
              ),
            ),
            expanded: _isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      ),
                    ),
                  )
                : (_similarArticles.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24.0),
                        child: Center(
                          child: Text(
                            '비슷한 한국어 작품이 없습니다.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          _buildArticleGrid(context, _similarArticles),
                          if (_similarArticles.length > 6)
                            _buildMoreButton(
                              context,
                              () => ArticleListPage(
                                cc: _similarArticles,
                                initialLanguage: 'korean',
                                name: '${Translations.instance!.trans('related')} ${Translations.instance!.trans('articles')}',
                              ),
                            ),
                        ],
                      )),
            collapsed: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildArticleGrid(BuildContext context, List<QueryResult> cc) {
    final windowWidth = MediaQuery.of(context).size.width;
    final displayItems = cc.take(6).toList();

    return LiveGrid(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      showItemInterval: const Duration(milliseconds: 40),
      showItemDuration: const Duration(milliseconds: 150),
      visibleFraction: 0.001,
      itemCount: displayItems.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3 / 4,
      ),
      itemBuilder: (context, index, animation) {
        final item = displayItems[index];
        return FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(animation),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.08),
              end: Offset.zero,
            ).animate(animation),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Provider<ArticleListItem>.value(
                value: ArticleListItem.fromArticleListItem(
                  queryResult: item,
                  showDetail: false,
                  addBottomPadding: false,
                  width: (windowWidth - 4.0) / 3,
                  thumbnailTag: 'similar_${item.id()}_$index',
                  usableTabList: cc,
                ),
                child: const ArticleListItemWidget(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoreButton(BuildContext context, Widget Function() what) {
    return SizedBox(
      height: 48,
      child: InkWell(
        onTap: () {
          PlatformNavigator.navigateSlide(context, what(), opaque: true);
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              Translations.instance!.trans('more'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }

  String _getReadableLanguage(String raw) {
    final lang = HybridLoader.normalizeLanguage(raw);
    switch (lang) {
      case 'korean':
        return '🇰🇷 한국어';
      case 'japanese':
        return '🇯🇵 日本語';
      case 'english':
        return '🇺🇸 English';
      case 'chinese':
        return '🇨🇳 中文';
      case 'spanish':
        return '🇪🇸 Español';
      default:
        return raw.isNotEmpty ? raw : '기타';
    }
  }
}
