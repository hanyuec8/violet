// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/component/query_translate.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/model/article_list_item.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/widgets/article_item/article_list_item_widget.dart';
import 'package:violet/widgets/debounce_widget.dart';
import 'package:violet/widgets/search_bar.dart';

class GroupArtistArticleList extends StatefulWidget {
  final String name;
  final int groupId;

  const GroupArtistArticleList({
    super.key,
    required this.name,
    required this.groupId,
  });

  @override
  State<GroupArtistArticleList> createState() => _GroupArtistArticleListState();
}

class _GroupArtistArticleListState extends State<GroupArtistArticleList>
    with AutomaticKeepAliveClientMixin<GroupArtistArticleList> {
  @override
  bool get wantKeepAlive => true;

  String _selectedLanguage = 'korean';
  bool _onlyNewReleases = false;
  bool _isLoading = true;
  List<QueryResult> _articles = [];
  Set<int> _bookmarkedArticleIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 북마크된 전체 작품 ID 로드
      final bms = await (await Bookmark.getInstance()).getArticle();
      _bookmarkedArticleIds = bms.map((e) => e.id()).toSet();

      // 2. 해당 그룹의 북마크 작가 목록 로드
      final artists = (await (await Bookmark.getInstance()).getArtist())
          .where((element) => element.group() == widget.groupId)
          .toList();

      if (artists.isEmpty) {
        if (mounted) {
          setState(() {
            _articles = [];
            _isLoading = false;
          });
        }
        return;
      }

      final langQuery =
          _selectedLanguage == 'all' ? '' : 'lang:$_selectedLanguage';

      // 3. 로컬 SQLite DB 일괄 조회 (0ms 즉시 응답)
      List<QueryResult> localArticles = [];
      try {
        final artistQueries = artists
            .map(
              (e) =>
                  '${e.type().name}:${e.artist().toLowerCase().replaceAll(' ', '_')}',
            )
            .join(' or ');
        final queryString = translate2query(
          '($artistQueries) $langQuery ${Settings.includeTags.value}',
        );
        final qm = QueryManager.queryPagination(queryString, 100);
        localArticles = await qm.next();
      } catch (_) {}

      // 로컬 결과가 있으면 최신작 모드가 아닐 때 0초 만에 화면 선반영
      if (localArticles.isNotEmpty && !_onlyNewReleases && mounted) {
        setState(() {
          _articles = localArticles;
          _isLoading = false;
        });
      }

      // 4. 각 작가별 온라인 Nozomi 인덱스 병렬 조회 (ID 목록 취득)
      final newReleaseIds = <int>[];
      final allCollectedIds = <int>[];

      await Future.wait(
        artists.map((artist) async {
          try {
            final url = HitomiNozomi.getArtistIndexUrl(
              artist.artist(),
              _selectedLanguage,
            );
            final ids = await HitomiNozomi.fetchGalleryIds(
              url,
              1,
              pageSize: 15,
            );

            if (ids.isNotEmpty) {
              allCollectedIds.addAll(ids);

              // 이 작가의 작품 중 사용자가 북마크한 최신 작품 품번(maxBookmarkedId) 찾기
              int maxBookmarkedId = 0;
              for (final id in ids) {
                if (_bookmarkedArticleIds.contains(id)) {
                  maxBookmarkedId = id;
                  break;
                }
              }

              // 북마크된 작품보다 최신인(품번이 더 큰) 신작들만 추출
              if (maxBookmarkedId > 0) {
                for (final id in ids) {
                  if (id > maxBookmarkedId) {
                    newReleaseIds.add(id);
                  } else {
                    break;
                  }
                }
              }
            }
          } catch (_) {}
        }),
      );

      // 5. 모아보기 모드에 따라 대상 ID 목록 결정
      final List<int> targetIds;
      if (_onlyNewReleases) {
        targetIds = newReleaseIds.toSet().toList();
      } else {
        final merged = <int>{
          ...allCollectedIds,
          ...localArticles.map((e) => e.id()),
        };
        targetIds = merged.toList();
      }

      if (targetIds.isEmpty) {
        if (mounted) {
          setState(() {
            _articles = [];
            _isLoading = false;
          });
        }
        return;
      }

      // 6. 대상 ID들의 메타데이터 복원 (로컬 DB + ArticleCache + 온라인 고속 조회)
      final resultMap = <int, QueryResult>{};
      for (final art in localArticles) {
        if (targetIds.contains(art.id())) {
          resultMap[art.id()] = art;
        }
      }

      final missingIds = targetIds.where((id) => !resultMap.containsKey(id)).toList();
      if (missingIds.isNotEmpty) {
        // 캐시 일괄 조회
        try {
          final cachedBatch = await HybridLoader.getCachedMetadataBatch(missingIds);
          for (final entry in cachedBatch.entries) {
            resultMap[entry.key] = entry.value;
          }
        } catch (_) {}

        // 아직도 메타데이터가 없는 신작들만 온라인 경량 파싱
        final stillMissing = missingIds.where((id) => !resultMap.containsKey(id)).toList();
        if (stillMissing.isNotEmpty) {
          final fetched = await Future.wait(
            stillMissing.take(20).map((id) => HybridLoader.idQueryHitomiFast(id)),
          );
          for (final art in fetched) {
            resultMap[art.id()] = art;
          }
        }
      }

      final finalArticles = resultMap.values.toList()
        ..sort((a, b) => b.id().compareTo(a.id()));

      if (mounted) {
        setState(() {
          _articles = finalArticles;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final windowWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final columnCount = isLandscape ? 4 : 3;

    return PrimaryScrollController(
      controller: ScrollController(),
      child: CupertinoScrollbar(
        scrollbarOrientation: Settings.bookmarkScrollbarPositionToLeft.value
            ? ScrollbarOrientation.left
            : ScrollbarOrientation.right,
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: <Widget>[
              SliverPersistentHeader(
                floating: true,
                delegate: AnimatedOpacitySliver(
                  searchBar: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Stack(
                      children: <Widget>[
                        _title(),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 6),
                  child: _controlBar(),
                ),
              ),
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              else if (_articles.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _onlyNewReleases
                              ? Icons.auto_awesome
                              : Icons.folder_open,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _onlyNewReleases
                              ? '북마크 이후 등록된 신작이 없습니다'
                              : '표시할 작품이 없습니다',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (_onlyNewReleases) ...[
                          const SizedBox(height: 6),
                          Text(
                            '등록된 작가의 최신 북마크 이후 나온 신작들이 여기에 모입니다.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columnCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 3 / 4,
                    ),
                    delegate: SliverChildListDelegate(
                      _articles.map((e) {
                        return DebounceWidget(
                          child: Padding(
                            key: Key('gaal/${e.id()}'),
                            padding: EdgeInsets.zero,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  Provider<ArticleListItem>.value(
                                    value: ArticleListItem.fromArticleListItem(
                                      queryResult: e,
                                      addBottomPadding: false,
                                      showDetail: false,
                                      width:
                                          (windowWidth - 4.0 - 52) /
                                          columnCount,
                                      thumbnailTag: const Uuid().v4(),
                                      usableTabList: _articles,
                                    ),
                                    child: const ArticleListItemWidget(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, left: 12),
      child: Text(
        _onlyNewReleases
            ? 'Artists New Releases (${_articles.length})'
            : 'Artists Article Collection (${_articles.length})',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _controlBar() {
    final langs = [
      ('한국어', 'korean'),
      ('일본어', 'japanese'),
      ('영어', 'english'),
      ('전체', 'all'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          // 최신작만 모아보기 토글 칩
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                _onlyNewReleases
                    ? Icons.auto_awesome
                    : Icons.auto_awesome_outlined,
                size: 16,
                color: _onlyNewReleases ? Colors.white : Colors.amber.shade700,
              ),
              label: Text(
                '최신작만',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _onlyNewReleases ? Colors.white : null,
                ),
              ),
              selected: _onlyNewReleases,
              selectedColor: Colors.deepOrangeAccent,
              checkmarkColor: Colors.white,
              onSelected: (val) {
                if (_onlyNewReleases != val) {
                  setState(() {
                    _onlyNewReleases = val;
                  });
                  _loadData();
                }
              },
            ),
          ),
          Container(
            height: 18,
            width: 1,
            color: Colors.grey.withValues(alpha: 0.3),
            margin: const EdgeInsets.only(right: 8.0),
          ),
          // 언어 필터 칩 목록 (이모티콘 없이 한국어 우선)
          ...langs.map((l) {
            final isSelected = _selectedLanguage == l.$2;
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  l.$1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : null,
                  ),
                ),
                selected: isSelected,
                selectedColor: Settings.majorColor.value,
                checkmarkColor: Colors.white,
                onSelected: (val) {
                  if (val && _selectedLanguage != l.$2) {
                    setState(() {
                      _selectedLanguage = l.$2;
                    });
                    _loadData();
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}
