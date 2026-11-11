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

  /// "202 pages", 202, "202" 등 다양한 타입의 페이지 수를 안전하게 정수로 파싱합니다.
  static int? parsePageCount(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final match = RegExp(r'\d+').firstMatch(raw);
      if (match != null) {
        return int.tryParse(match.group(0)!);
      }
    }
    return null;
  }

  /// 작품의 태그 목록 중 장르와 캐릭터성을 가장 강력하게 특정하는 핵심 태그를 선별합니다.
  static String? extractPrimaryGenreTag(QueryResult current) {
    final rawTags = (current.tags() ?? '')
        .split('|')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty && e != 'n/a')
        .toList();

    if (rawTags.isEmpty) return null;

    const nonGenreTags = <String>{
      'rough translation',
      'translation',
      'translated',
      'digital',
      'uncensored',
      'decensored',
      'tankoubon',
      'anthology',
      'color',
      'full color',
      'rewrite',
      'sample',
      'incomplete',
      'variant set',
      'compilation',
      'artbook',
      'webtoon',
      'comic',
      'manga',
      'doujinshi',
    };

    // 캐릭터성 및 장르를 강력하게 특정하는 우선 키워드 (우선순위 순)
    const priorityKeywords = <String>[
      'gyaru',
      'tall girl',
      'tomboy',
      'yandere',
      'tsundere',
      'maid',
      'milf',
      'shota',
      'bbm',
      'dilf',
      'crossdressing',
      'femdom',
      'dark skin',
      'tan',
      'netorare',
      'ntr',
      'cheating',
      'incest',
      'mind break',
      'twins',
      'cosplay',
      'monster girl',
      'elf',
      'goth',
      'ojousama',
      'delinquent',
      'teacher',
      'schoolgirl uniform',
      'swimsuit',
      'bikini',
      'cheerleader',
      'stockings',
      'glasses',
      'emotionless sex',
      'squirting',
      'big breasts',
      'small breasts',
    ];

    final filtered = rawTags.where((t) => !nonGenreTags.contains(t)).toList();
    if (filtered.isEmpty) return null;

    // 점수화 기반 최고 순위 태그 선정
    String? bestTag;
    int highestScore = -1;

    for (final tag in filtered) {
      int score = 0;
      final cleanTag = tag.replaceFirst(RegExp(r'^(female|male):'), '');

      // 우선 키워드 인덱스 기반 가산점
      for (int i = 0; i < priorityKeywords.length; i++) {
        if (cleanTag == priorityKeywords[i] || cleanTag.contains(priorityKeywords[i])) {
          score += 200 - (i * 3);
          break;
        }
      }

      if (tag.startsWith('female:')) {
        score += 50;
      } else if (tag.startsWith('male:')) {
        score += 30;
      }

      if (score > highestScore) {
        highestScore = score;
        bestTag = tag;
      }
    }

    return bestTag ?? filtered.first;
  }

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

    // -------------------------------------------------------------
    // 1단계: Hitomi 공식 related 추천작 수집 (Hitomi 엔진의 엄선 연관작 5개)
    // -------------------------------------------------------------
    try {
      final galleryInfo = await FirstPageGrouper.getGalleryInfo(currentId);
      if (galleryInfo != null && galleryInfo['related'] is List) {
        final relatedRaw = galleryInfo['related'] as List;
        final relatedIds = relatedRaw
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .where((id) => !seenIds.contains(id))
            .take(5)
            .toList();

        if (relatedIds.isNotEmpty) {
          final cachedBatch = await HybridLoader.getCachedMetadataBatch(relatedIds);
          final missingIds = <int>[];

          for (final id in relatedIds) {
            if (cachedBatch.containsKey(id)) {
              final item = cachedBatch[id]!;
              if (seenIds.add(item.id())) {
                results.add(item);
              }
            } else {
              missingIds.add(id);
            }
          }

          if (missingIds.isNotEmpty) {
            await Future.wait(
              missingIds.map((id) async {
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

    // 작가 추출
    final artistStr = current.artists() ?? '';
    final artists = artistStr
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'n/a')
        .toList();

    // -------------------------------------------------------------
    // 2단계: 작가가 있는 경우 - 유사 화풍 다른 작가(Similar Artists) 매칭 (타 작가 발굴)
    // -------------------------------------------------------------
    if (results.length < 12 && artists.isNotEmpty) {
      try {
        final similarArtists = HentaiIndex.calculateSimilarArtists(artists.first);
        for (final (simArtist, _) in similarArtists.take(2)) {
          if (results.length >= 12) break;
          try {
            final simArticles = await HybridLoader.fetchArtistArticlesHybrid(
              name: simArtist,
              type: 'artist',
              pageSize: 4,
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

    // -------------------------------------------------------------
    // 3단계: 작가가 있는 경우 - 동일 작가 대표작 안배 (최대 2~3개로 캡을 씌워 타 작가 공간 보장)
    // -------------------------------------------------------------
    if (results.length < 12 && artists.isNotEmpty) {
      try {
        final artistArticles = await HybridLoader.fetchArtistArticlesHybrid(
          name: artists.first,
          type: 'artist',
          pageSize: 10,
          language: 'korean',
        );
        int artistAddedCount = 0;
        for (final art in artistArticles) {
          if (artistAddedCount >= 3) break;
          if (seenIds.add(art.id())) {
            results.add(art);
            artistAddedCount++;
            if (results.length >= 12) break;
          }
        }
      } catch (_) {}
    }

    // -------------------------------------------------------------
    // 4단계: 핵심 캐릭터·장르 태그 기반 실시간 한국어 작품 수집 (타 작가 유사작 보강의 핵심!)
    // -------------------------------------------------------------
    if (results.length < 12) {
      try {
        final primaryTag = SimilarArticleSection.extractPrimaryGenreTag(current);
        if (primaryTag != null && primaryTag.isNotEmpty) {
          final neededCount = 12 - results.length;
          final tagIds = await HybridLoader.fetchGalleryIdsForQuery(
            query: primaryTag,
            page: 1,
            pageSize: neededCount + 10,
            targetLang: 'korean',
          ).timeout(const Duration(milliseconds: 2500));

          final validIds = tagIds.where((id) => !seenIds.contains(id)).take(neededCount).toList();
          if (validIds.isNotEmpty) {
            final cachedBatch = await HybridLoader.getCachedMetadataBatch(validIds);
            final missingIds = <int>[];

            for (final id in validIds) {
              if (cachedBatch.containsKey(id)) {
                final item = cachedBatch[id]!;
                if (seenIds.add(item.id())) {
                  results.add(item);
                }
              } else {
                missingIds.add(id);
              }
            }

            if (missingIds.isNotEmpty) {
              await Future.wait(
                missingIds.map((id) async {
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

    // -------------------------------------------------------------
    // 5단계: 작가가 없거나 여전히 부족한 경우 기존 연관 DB(related.json) 최종 폴백
    // -------------------------------------------------------------
    if (results.length < 6) {
      try {
        await Related.ensureLoaded();
        if (Related.existsRelated(currentId)) {
          final relatedIds = Related.getRelated(currentId)
              .where((id) => !seenIds.contains(id))
              .take(12 - results.length)
              .toList();

          if (relatedIds.isNotEmpty) {
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

    // 한국어 작품 최우선 정렬 및 최신순 정렬 (사용자 원칙: "한국어 작품을 기본으로 보여줄 것")
    results.sort((a, b) {
      final isKoreanA = HybridLoader.normalizeLanguage(a.language()?.toString() ?? '') == 'korean';
      final isKoreanB = HybridLoader.normalizeLanguage(b.language()?.toString() ?? '') == 'korean';
      if (isKoreanA != isKoreanB) {
        return isKoreanA ? -1 : 1;
      }
      return b.id().compareTo(a.id());
    });

    return results.take(12).toList();
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
                final count = SimilarArticleSection.parsePageCount(v.files());
                final pageCount = count != null && count > 0 ? '${count}p' : '';

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
