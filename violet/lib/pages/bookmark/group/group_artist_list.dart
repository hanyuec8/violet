// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:mdi/mdi.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/component/index.dart';
import 'package:violet/component/query_translate.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/model/article_list_item.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/artist_info/artist_info_page.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/style/palette.dart';
import 'package:violet/widgets/article_item/article_list_item_widget.dart';
import 'package:violet/widgets/debounce_widget.dart';
import 'package:violet/widgets/floating_button.dart';
import 'package:violet/widgets/search_bar.dart';

class GroupArtistList extends StatefulWidget {
  final String name;
  final int groupId;

  const GroupArtistList({super.key, required this.name, required this.groupId});

  @override
  State<GroupArtistList> createState() => _GroupArtistListState();
}

class _GroupArtistListState extends State<GroupArtistList>
    with AutomaticKeepAliveClientMixin<GroupArtistList> {
  @override
  bool get wantKeepAlive => true;

  late List<BookmarkArtist> artists = [];
  final Map<String, int> _artistCountCache = <String, int>{};
  final Map<String, List<QueryResult>> _artistThumbnailCache =
      <String, List<QueryResult>>{};

  String _selectedLanguage = 'all';
  Set<int> _bookmarkedArticleIds = {};
  bool _isSearching = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  int _filterLevel = 0; // 0: 북마크순, 1: 최신품번순, 2: 신작있는작가우선순
  bool _progressingFilter = false;

  @override
  void initState() {
    super.initState();
    _loadBookmarkedArticleIds();
  }

  Future<void> _loadBookmarkedArticleIds() async {
    try {
      final bms = await (await Bookmark.getInstance()).getArticle();
      if (mounted) {
        setState(() {
          _bookmarkedArticleIds = bms.map((e) => e.id()).toSet();
        });
      }
    } catch (_) {}
  }

  Future<List<BookmarkArtist>> _bookmark() async {
    if (_filterLevel == 0 && artists.isEmpty) {
      await refresh();
    }
    return _filteredArtists;
  }

  List<BookmarkArtist> get _filteredArtists {
    if (_searchQuery.trim().isEmpty) return artists;
    final q = _searchQuery.trim().toLowerCase();
    return artists.where((e) => e.artist().toLowerCase().contains(q)).toList();
  }

  int _getNewReleaseCount(List<QueryResult> articles) {
    if (articles.isEmpty || _bookmarkedArticleIds.isEmpty) return 0;
    int bookmarkedIndex = -1;
    for (int i = 0; i < articles.length; i++) {
      if (_bookmarkedArticleIds.contains(articles[i].id())) {
        bookmarkedIndex = i;
        break;
      }
    }
    if (bookmarkedIndex > 0) {
      return bookmarkedIndex;
    }
    return 0;
  }

  Future<void> _sortByLatest() async {
    var ids = <(int, int)>[];
    for (int i = 0; i < artists.length; i++) {
      final a = artists[i];
      final cacheKey = '${a.type().name}:${a.artist()}:$_selectedLanguage';
      final cached = _artistThumbnailCache[cacheKey];
      var query = (cached != null && cached.isNotEmpty) ? cached[0].id() : 0;

      if (query == 0) {
        try {
          final f = await _future(a.artist(), a.type(), _selectedLanguage);
          if (f.isNotEmpty) query = f[0].id();
        } catch (_) {}
      }

      ids.add((query, i));
    }
    ids.sort((e1, e2) => e2.$1.compareTo(e1.$1));

    var newedList = <BookmarkArtist>[];
    for (int i = 0; i < artists.length; i++) {
      newedList.add(artists[ids[i].$2]);
    }

    artists = newedList;
  }

  Future<void> _sortByNewReleases() async {
    await Future.wait(
      artists.map((a) => _future(a.artist(), a.type(), _selectedLanguage)),
    );

    var pairs = <(int, int, int)>[]; // (newCount, latestId, index)
    for (int i = 0; i < artists.length; i++) {
      final a = artists[i];
      final cacheKey = '${a.type().name}:${a.artist()}:$_selectedLanguage';
      final qq = _artistThumbnailCache[cacheKey] ?? [];
      final newCount = _getNewReleaseCount(qq);
      final latestId = qq.isNotEmpty ? qq[0].id() : 0;
      pairs.add((newCount, latestId, i));
    }

    pairs.sort((e1, e2) {
      final c1 = e2.$1.compareTo(e1.$1); // newCount 내림차순
      if (c1 != 0) return c1;
      return e2.$2.compareTo(e1.$2); // 최신 품번 내림차순
    });

    artists = pairs.map((p) => artists[p.$3]).toList();
  }

  Future<List<QueryResult>> _future(
    String e,
    ArtistType type, [
    String? lang,
  ]) async {
    final targetLang = lang ?? _selectedLanguage;
    final cacheKey = '${type.name}:$e:$targetLang';
    if (_artistThumbnailCache.containsKey(cacheKey)) {
      return _artistThumbnailCache[cacheKey]!;
    }

    var postfix = e.toLowerCase().replaceAll(' ', '_');
    var langQuery = targetLang == 'all' ? '' : 'lang:$targetLang';
    var queryString = translate2query(
      '${type.name}:$postfix $langQuery ${Settings.includeTags.value}',
    );
    final qm = QueryManager.queryPagination(queryString, 4);
    final localResults = await qm.next();
    if (localResults.isNotEmpty) {
      _artistThumbnailCache[cacheKey] = localResults;
      return localResults;
    }

    // 로컬 DB 부재 시 하이브리드 로더로 최신 작품 4개 썸네일 조회
    try {
      final hybrid = await HybridLoader.fetchArtistArticlesHybrid(
        name: e,
        type: type.name,
        pageSize: 4,
        language: targetLang,
      );
      if (hybrid.isNotEmpty) {
        final list = hybrid.take(4).toList();
        _artistThumbnailCache[cacheKey] = list;

        // 총 작품 수 비동기 조회 및 실시간 카운트 갱신
        final nozomiUrl = HitomiNozomi.getArtistIndexUrl(e, targetLang);
        HitomiNozomi.getTotalCount(nozomiUrl).then((cnt) {
          if (cnt != null && cnt > 0 && mounted) {
            setState(() {
              _artistCountCache[cacheKey] = cnt;
            });
          }
        });

        return list;
      }
    } catch (_) {}

    return [];
  }

  Future<void> refresh() async {
    artists = (await (await Bookmark.getInstance()).getArtist())
        .where((element) => element.group() == widget.groupId)
        .toList()
        .reversed
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final filtered = _filteredArtists;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      floatingActionButton: Visibility(
        visible: checkMode,
        child: AnimatedOpacity(
          opacity: checkModePre ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: _floatingButton(),
        ),
      ),
      body: FutureBuilder<List<BookmarkArtist>>(
        future: _bookmark(),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<BookmarkArtist>> snapshot,
        ) {
          if (!snapshot.hasData) return Container();
          return PrimaryScrollController(
            controller: ScrollController(),
            child: CupertinoScrollbar(
              scrollbarOrientation:
                  Settings.bookmarkScrollbarPositionToLeft.value
                      ? ScrollbarOrientation.left
                      : ScrollbarOrientation.right,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: <Widget>[
                  SliverPersistentHeader(
                    floating: true,
                    delegate: AnimatedOpacitySliver(
                      searchBar: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Stack(
                          children: <Widget>[
                            _filter(),
                            _searchButton(),
                            _title(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: _languageChips(),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      var e = filtered[index];
                      return FutureBuilder<List<QueryResult>>(
                        future: _future(e.artist(), e.type()),
                        builder: (
                          BuildContext context,
                          AsyncSnapshot<List<QueryResult>> snapshot,
                        ) {
                          if (!snapshot.hasData) {
                            return Container(height: 195);
                          }
                          return _listItem(context, e, snapshot.data!);
                        },
                      );
                    }, childCount: _progressingFilter ? 0 : filtered.length),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _languageChips() {
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
        children: langs.map((l) {
          final isSelected = _selectedLanguage == l.$2;
          return Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: FilterChip(
              visualDensity: VisualDensity.compact,
              label: Text(
                l.$1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _searchButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 56.0),
        child: Hero(
          tag: 'searchtype_artist_search',
          child: Card(
            color: Palette.themeColor,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            elevation: !Settings.themeFlat.value ? 100 : 0,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                  }
                });
              },
              child: SizedBox(
                height: 48,
                width: 48,
                child: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  color: _isSearching ? Settings.majorColor.value : Colors.grey,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _filter() {
    return Align(
      alignment: Alignment.centerRight,
      child: Hero(
        tag: 'searchtype3',
        child: Card(
          color: Palette.themeColor,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8.0)),
          ),
          elevation: !Settings.themeFlat.value ? 100 : 0,
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: InkWell(
            onTap: _progressingFilter
                ? null
                : () async {
                    setState(() {
                      _progressingFilter = true;
                    });
                    final nextLevel = (_filterLevel + 1) % 3;
                    if (nextLevel == 0) {
                      await refresh();
                    } else if (nextLevel == 1) {
                      await _sortByLatest();
                    } else if (nextLevel == 2) {
                      await _sortByNewReleases();
                    }
                    if (mounted) {
                      setState(() {
                        _progressingFilter = false;
                        _filterLevel = nextLevel;
                      });
                    }
                  },
            child: SizedBox(
              height: 48,
              width: 48,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  _progressingFilter
                      ? const SizedBox(
                          height: 30,
                          width: 30,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.grey,
                            ),
                          ),
                        )
                      : Icon(
                          [
                            MdiIcons.formatListText,
                            Mdi.sortClockDescendingOutline,
                            Icons.auto_awesome,
                          ][_filterLevel],
                          color: _filterLevel == 2
                              ? Colors.redAccent
                              : Colors.grey,
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title() {
    if (_isSearching) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, left: 12, right: 110),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '작가 이름 검색...',
            isDense: true,
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey.shade500),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
        ),
      );
    }

    String sortDesc = '';
    if (_filterLevel == 1) sortDesc = ' (최신순)';
    if (_filterLevel == 2) sortDesc = ' (신작 우선)';

    return Padding(
      padding: const EdgeInsets.only(top: 24, left: 12),
      child: Text(
        'Artists Collection$sortDesc',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
    );
  }

  int _resolveArticleCount(BookmarkArtist e, List<QueryResult> qq) {
    final cacheKey = '${e.type().name}:${e.artist()}:$_selectedLanguage';
    if (_artistCountCache.containsKey(cacheKey)) {
      return _artistCountCache[cacheKey]!;
    }
    final dbCount = HentaiIndex.getArticleCount(e.type().name, e.artist());
    if (dbCount > 0) return dbCount;

    if (qq.isNotEmpty) {
      return qq.length;
    }
    return 0;
  }

  Widget _listItem(
    BuildContext context,
    BookmarkArtist e,
    List<QueryResult> qq,
  ) {
    final windowWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final columnCount = isLandscape ? 4 : 3;
    final subItemWidth = (windowWidth - 16 - 4.0 - 1.0) / columnCount;

    const kHeaderHeight = 33;
    const childAspectRatio = 3 / 4;
    final height = windowWidth / columnCount / childAspectRatio;
    final newCount = _getNewReleaseCount(qq);

    return Container(
      color:
          checkMode &&
                  checked
                      .where(
                        (element) =>
                            element.$1 == e.type() && element.$2 == e.artist(),
                      )
                      .isNotEmpty
              ? Colors.amber
              : Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (checkMode) {
            check(
              e.type(),
              e.artist(),
              checked
                  .where(
                    (element) =>
                        element.$1 == e.type() && element.$2 == e.artist(),
                  )
                  .isEmpty,
            );
            setState(() {});
            return;
          }

          PlatformNavigator.navigateSlide(
            context,
            ArtistInfoPage(name: e.artist(), type: e.type()),
          );
        },
        onLongPress: checkMode
            ? null
            : () {
                longpress(e.type(), e.artist());
              },
        child: SizedBox(
          height: height + kHeaderHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              ' ${e.type().name}:${e.artist()} (${_resolveArticleCount(e, qq)})',
                              style: const TextStyle(fontSize: 17),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (newCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'NEW +$newCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: height,
                  child: DebounceWidget(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _image(qq, 0, subItemWidth),
                        _image(qq, 1, subItemWidth),
                        _image(qq, 2, subItemWidth),
                        if (isLandscape) _image(qq, 3, subItemWidth),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(List<QueryResult> qq, int index, double subItemWidth) {
    return Expanded(
      flex: 1,
      child: qq.length > index
          ? Padding(
              key: Key('${qq[index].id()}/${index}_thumbnail_bookmark'),
              padding: const EdgeInsets.all(4),
              child: Provider<ArticleListItem>.value(
                value: ArticleListItem.fromArticleListItem(
                  queryResult: qq[index],
                  showDetail: false,
                  addBottomPadding: false,
                  width: subItemWidth,
                  thumbnailTag: const Uuid().v4(),
                  disableFilter: true,
                  usableTabList: qq,
                ),
                child: const ArticleListItemWidget(),
              ),
            )
          : Container(),
    );
  }

  Widget _floatingButton() {
    return AnimatedFloatingActionButton(
      fabButtons: <Widget>[
        FloatingActionButton(
          onPressed: () {
            for (var element in artists) {
              checked.add((element.type(), element.artist()));
            }
            setState(() {});
          },
          elevation: 4,
          heroTag: 'a',
          child: const Icon(MdiIcons.checkAll),
        ),
        FloatingActionButton(
          onPressed: () async {
            if (await showYesNoDialog(
              context,
              Translations.instance!
                  .trans('deletebookmarkmsg')
                  .replaceAll('%s', checked.length.toString()),
              Translations.instance!.trans('bookmark'),
            )) {
              var bookmark = await Bookmark.getInstance();
              for (var element in checked) {
                await bookmark.unbookmarkArtist(element.$2, element.$1);
              }
              checked.clear();
              refresh();
              setState(() {
                checkModePre = false;
                checked.clear();
              });
              Future.delayed(const Duration(milliseconds: 500)).then((value) {
                setState(() {
                  checkMode = false;
                });
              });
            }
          },
          elevation: 4,
          heroTag: 'b',
          child: const Icon(MdiIcons.delete),
        ),
        FloatingActionButton(
          onPressed: moveChecked,
          elevation: 4,
          heroTag: 'c',
          child: const Icon(MdiIcons.folderMove),
        ),
      ],
      animatedIconData: AnimatedIcons.menu_close,
      exitCallback: () {
        setState(() {
          checkModePre = false;
          checked.clear();
        });
        Future.delayed(const Duration(milliseconds: 500)).then((value) {
          setState(() {
            checkMode = false;
          });
        });
      },
    );
  }

  bool checkMode = false;
  bool checkModePre = false;
  List<(ArtistType, String)> checked = [];

  void longpress(ArtistType type, String artist) {
    if (!checkMode) {
      checkMode = true;
      checkModePre = true;
      checked.add((type, artist));
      setState(() {});
    }
  }

  void check(ArtistType type, String artist, bool check) {
    if (check) {
      checked.add((type, artist));
    } else {
      checked.removeWhere(
        (element) => element.$1 == type && element.$2 == artist,
      );
      if (checked.isEmpty) {
        setState(() {
          checkModePre = false;
          checked.clear();
        });
        Future.delayed(const Duration(milliseconds: 500)).then((value) {
          setState(() {
            checkMode = false;
          });
        });
      }
    }
  }

  Future<void> moveChecked() async {
    var groups = await (await Bookmark.getInstance()).getGroup();
    var currentGroup = widget.groupId;
    groups = groups
        .where(
          (e) => e.id() != currentGroup && !Bookmark.isDefaultGroupId(e.id()),
        )
        .toList();
    int choose = -9999;
    if (!mounted) return;
    if (await showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(Translations.instance!.trans('wheretomove')),
            actions: <Widget>[
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Settings.majorColor.value,
                ),
                child: Text(Translations.instance!.trans('cancel')),
                onPressed: () {
                  Navigator.pop(context, 0);
                },
              ),
            ],
            content: SizedBox(
              width: 200,
              height: 300,
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(groups[index].name()),
                    subtitle: Text(groups[index].description()),
                    onTap: () {
                      choose = index;
                      Navigator.pop(context, 1);
                    },
                  );
                },
              ),
            ),
          ),
        ) ==
        1) {
      if (!mounted) return;
      if (await showYesNoDialog(
        context,
        Translations.instance!
            .trans('movetoto')
            .replaceAll('%1', groups[choose].name())
            .replaceAll('%2', checked.length.toString()),
        Translations.instance!.trans('movebookmark'),
      )) {
        var invIdIndex = <String, int>{};
        for (int i = 0; i < artists.length; i++) {
          invIdIndex['${artists[i].artist()}|${artists[i].type()}'] = i;
        }
        checked.sort(
          (x, y) => invIdIndex['${x.$2}|${x.$1}']!.compareTo(
            invIdIndex['${y.$2}|${y.$1}']!,
          ),
        );

        var bm = await Bookmark.getInstance();
        for (var e in checked.reversed) {
          await bm.unbookmarkArtist(e.$2, e.$1);
          await bm.insertArtist(e.$2, e.$1, DateTime.now(), groups[choose].id());
        }
        checked.clear();
        refresh();
        setState(() {
          checkModePre = false;
          checked.clear();
        });
        Future.delayed(const Duration(milliseconds: 500)).then((value) {
          setState(() {
            checkMode = false;
          });
        });
      }
    }
  }
}
