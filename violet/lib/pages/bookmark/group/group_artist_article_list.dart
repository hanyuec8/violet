// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
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

  String _selectedLanguage = 'all';
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

      // 3. 작가별 작품 병렬 수집 (로컬 쿼리 + 온라인 하이브리드 로더)
      final resultsPerArtist = await Future.wait(
        artists.map((artist) async {
          List<QueryResult> artistArticles = [];

          // (1) 로컬 DB 쿼리 우선 시도
          try {
            final queryString = translate2query(
              '${artist.type().name}:${artist.artist().toLowerCase().replaceAll(' ', '_')} $langQuery ${Settings.includeTags.value}',
            );
            final qm = QueryManager.queryPagination(queryString, 30);
            artistArticles = await qm.next();
          } catch (_) {}

          // (2) 로컬 결과가 비어있거나 온라인 최신작 수집이 필요한 경우 HybridLoader 연동
          if (artistArticles.isEmpty) {
            try {
              final hybrid = await HybridLoader.fetchArtistArticlesHybrid(
                name: artist.artist(),
                type: artist.type().name,
                pageSize: 30,
                language: _selectedLanguage,
              );
              if (hybrid.isNotEmpty) {
                artistArticles = hybrid;
              }
            } catch (_) {}
          }

          // 최신 품번 내림차순 정렬
          artistArticles.sort((a, b) => b.id().compareTo(a.id()));

          // (3) '최신작만 모아보기' 필터 적용
          if (_onlyNewReleases) {
            if (_bookmarkedArticleIds.isEmpty || artistArticles.isEmpty) {
              return <QueryResult>[];
            }
            final firstBookmarkedIndex = artistArticles.indexWhere(
              (art) => _bookmarkedArticleIds.contains(art.id()),
            );
            // 북마크된 첫 번째 작품보다 앞에 있는 최신 등록 작품들만 신작으로 추출
            if (firstBookmarkedIndex > 0) {
              return artistArticles.sublist(0, firstBookmarkedIndex);
            }
            return <QueryResult>[];
          }

          return artistArticles;
        }),
      );

      // 4. 모든 작가의 작품을 병합하고 중복 제거 후 최신순 정렬
      final Map<int, QueryResult> articleMap = {};
      for (final list in resultsPerArtist) {
        for (final art in list) {
          articleMap[art.id()] = art;
        }
      }

      final sortedArticles = articleMap.values.toList()
        ..sort((a, b) => b.id().compareTo(a.id()));

      if (mounted) {
        setState(() {
          _articles = sortedArticles;
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
      ('전체', 'all'),
      ('🇰🇷 한국어', 'korean'),
      ('🇯🇵 일본어', 'japanese'),
      ('🇺🇸 영어', 'english'),
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
                _onlyNewReleases ? Icons.auto_awesome : Icons.auto_awesome_outlined,
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
          // 언어 필터 칩 목록
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
