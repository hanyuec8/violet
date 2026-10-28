// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:async';

import 'package:flare_flutter/flare_cache.dart';
import 'package:flare_flutter/flare_controls.dart';
import 'package:flare_flutter/provider/asset_flare.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:get/get.dart';
import 'package:violet/component/hentai.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/component/hitomi/population.dart';
import 'package:violet/context/modal_bottom_sheet_context.dart';
import 'package:violet/database/query.dart';
import 'package:violet/log/log.dart';
import 'package:violet/pages/segment/filter_page_controller.dart';
import 'package:violet/script/script_manager.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/thread/semaphore.dart';

class SearchPageController extends GetxController {
  final FlareControls heroFlareControls = FlareControls();
  late AssetFlare asset;

  FilterController filterController = FilterController(
    heroKey: 'searchtype${ModalBottomSheetContext.getCount()}',
  );

  ScrollController? scrollController;
  Map<String, GlobalKey> itemKeys = <String, GlobalKey>{};

  final List<int> _scrollQueue = <int>[];
  double _itemHeight = 0.0;
  bool _scrollInProgress = false;
  bool _queryEnd = false;

  static const int defaultPageSize = 50;

  final Rx<SearchSortMode> searchSortMode = Settings.searchSortMode.value.obs;

  var isExtended = false.obs;
  var searchPageNum = 0.obs;
  var searchTotalResultCount = 0.obs;

  final Semaphore _querySem = Semaphore(maxCount: 1);
  (SearchResult?, String)? latestQuery;
  List<QueryResult> queryResult = [];
  List<QueryResult> filterResult = [];
  int baseCount = 0; // using for user custom page index
  bool isFilterUsed = false;

  var isPupilFilterUsed = false.obs;
  var isPupilFilterLoading = false.obs;
  List<QueryResult> pupilFilterResult = [];
  int pupilFilterPage = 1;
  int mainHybridPage = 1;

  final void Function({bool isAppend}) reloadForce;

  SearchPageController({required this.reloadForce});

  init(BuildContext context) {
    asset = AssetFlare(
      bundle: rootBundle,
      name: 'assets/flare/search_close.flr',
    );
    cachedActor(asset);
  }

  initScroll(BuildContext context) {
    if (scrollController == null) {
      scrollController = ScrollController();
      scrollController!.addListener(scrollPositionListener);
    }
  }

  /// 현재 검색 대상이 한국어(lang:korean)인지 판별합니다.
  bool isCurrentSearchKorean() {
    final query = latestQuery?.$2.trim().toLowerCase() ?? '';
    final match = RegExp(r'(?:^|\s)(?:lang|language):([a-zA-Z가-힣]+)', caseSensitive: false).firstMatch(query);
    if (match != null) {
      final lang = match.group(1)!.toLowerCase();
      return lang == 'korean' || lang == '한국어';
    }
    // 쿼리에 타 언어가 명시되지 않은 경우 기본 검색 설정 언어 확인
    if (!query.contains('lang:') && !query.contains('language:')) {
      final selectedLangs = HybridLoader.getSelectedLanguages();
      return selectedLangs.length == 1 && selectedLangs.first == 'korean';
    }
    return false;
  }

  scrollPositionListener() {
    //
    // scroll position
    //
    if (itemKeys.isNotEmpty && _itemHeight <= 0.1) {
      for (var key in itemKeys.entries) {
        // invisible article is not rendered yet
        // so we can find live elements
        if (key.value.currentContext != null) {
          final bottomPadding = [
            8,
            8,
            0,
            0,
            0,
          ][Settings.searchResultType.value.index];
          _itemHeight = key.value.currentContext!.size!.height + bottomPadding;
          break;
        }
      }
    }

    if (scrollController!.offset.isNaN) return;

    final itemPerRow = [3, 2, 1, 1, 1][Settings.searchResultType.value.index];
    const headerHeight = 76.0;
    final fallbackHeight = [200.0, 250.0, 130.0, 130.0, 220.0][Settings.searchResultType.value.index];
    final effectiveHeight = _itemHeight > 0.1 ? _itemHeight : fallbackHeight;
    final relativeOffset = (scrollController!.offset - headerHeight).clamp(0.0, double.infinity);
    final rawRow = relativeOffset / effectiveHeight;
    final maxIndex = (getSearchList().length - 1).clamp(0, 1000000);
    final curI = (rawRow.floor() * itemPerRow).clamp(0, maxIndex);

    if (curI != searchPageNum.value) {
      searchPageNum.value = curI;

      // 사용자가 직접 화면을 스크롤하고 있을 때만 위치 및 마지막 본 작품을 실시간 영구 보관합니다.
      // (태그 검색 직후 jumpTo(0) 등 시스템 이동에 의해 직전 감상 위치/작품 기록이 리셋되는 것을 원천 방지)
      final isUserScrolling = scrollController?.hasClients == true &&
          scrollController!.position.userScrollDirection != ScrollDirection.idle;

      // lang:korean 및 pupil 기능을 켰을 때만 마지막으로 본 위치를 기억합니다 (그 외에는 절대 기록하지 않음).
      final canRecordLastPosition = isPupilFilterUsed.value && isCurrentSearchKorean();

      if (isUserScrolling && canRecordLastPosition) {
        final absolutePosition = curI + baseCount;
        if (Settings.lastSearchPosition.value != absolutePosition) {
          Settings.lastSearchPosition.setValue(absolutePosition);
        }

        final list = getSearchList();
        if (curI >= 0 && curI < list.length) {
          final item = list[curI];
          final id = item.id();
          if (id > 0 && Settings.lastSearchArticleId.value != id) {
            Settings.lastSearchArticleId.setValue(id);
            Settings.lastSearchArticleTitle.setValue(item.title() ?? '');
            Settings.lastSearchIsPupil.setValue(true);
          }
        }
      }
    }

    //
    // scroll direction
    //
    var upScrolling =
        scrollController!.position.userScrollDirection ==
        ScrollDirection.forward;

    if (upScrolling) {
      _scrollQueue.add(-1);
    } else {
      _scrollQueue.add(1);
    }

    if (_scrollQueue.length > 64) {
      _scrollQueue.removeRange(0, _scrollQueue.length - 65);
    }

    var p = _scrollQueue.reduce((value, element) => value + element);

    if (p <= -32 && !isExtended.value) {
      isExtended.value = true;
    } else if (p >= 32 && isExtended.value) {
      isExtended.value = false;
    }

    //
    //  scroll lazy next query loading
    //
    if (_scrollInProgress || _queryEnd) return;
    final maxScroll = scrollController!.position.maxScrollExtent;
    final curOffset = scrollController!.offset;

    final isTrigger = isPupilFilterUsed.value
        ? (maxScroll > 50 && curOffset > maxScroll * 0.2)
        : (maxScroll > 200 && curOffset > maxScroll * 0.6);

    if (isTrigger) {
      _scrollInProgress = true;
      Future.delayed(const Duration(milliseconds: 100), () async {
        try {
          await loadNextQuery();
        } catch (e) {
          print('loadNextQuery failed: $e');
        } finally {
          _scrollInProgress = false;
        }
      }).catchError((e) {
        _scrollInProgress = false;
      });
    }
  }

  resetItemHeight() => _itemHeight = 0.0;

  showErrorToast(String message) {
    FToast().showToast(
      toastDuration: const Duration(seconds: 10),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(),
          borderRadius: const BorderRadius.all(Radius.circular(8.0)),
        ),
        child: Text(message),
      ),
    );
  }

  loadNextQuery() async {
    final aquire = _querySem.acquire();
    if (!Settings.ignoreTimeout.value) {
      aquire.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          Logger.warning('[loadNextQuery] Query semaphore acquisition timed out');
          throw TimeoutException('Failed to acquire the query semaphore');
        },
      );
    }
    await aquire;

    if (isPupilFilterUsed.value) {
      isPupilFilterLoading.value = true;
    }

    try {
      if (_queryEnd) {
        return;
      }

      final query = latestQuery?.$2 ?? '';

      // 메인페이지와 동일한 고속 하이브리드 로더(0.3~0.5s)를 사용합니다.
      // Pupil 필터 상태:
      // - 현재 누적된 Pupil 단독작이 12개 미만인 경우, 화면에 스크롤바가 생길 수 있도록 최소 12개 이상이 될 때까지 연속으로 빠르게 채웁니다.
      // - 이미 12개 이상 확보되어 스크롤이 가능한 상태라면 스크롤 시 1~2회 배치(0.3~0.5초)로 가볍게 새 작품들을 덧붙입니다.
      int attempts = 0;
      final targetCount = isPupilFilterUsed.value
          ? (pupilFilterResult.length < 12 ? 12 : pupilFilterResult.length + 3)
          : 0;
      final maxAttempts = isPupilFilterUsed.value
          ? (pupilFilterResult.length < 12 ? 8 : 2)
          : 1;

      while (attempts < maxAttempts) {
        attempts++;
        final hybridList = await HybridLoader.fetchMainHybridArticles(
          query: query,
          page: mainHybridPage,
          pageSize: defaultPageSize,
          sortMode: searchSortMode.value,
        );
        mainHybridPage++;

        if (hybridList.isEmpty) {
          _queryEnd = true;
          break;
        }

        // 중복 방지 (기존 queryResult에 이미 존재하는 ID는 제외)
        final existingIds = queryResult.map((e) => e.id()).toSet();
        final newUnique = hybridList.where((e) => !existingIds.contains(e.id())).toList();
        if (newUnique.isEmpty) continue;

        queryResult.addAll(newUnique);

        // Pupil 단독작 선별 및 pupilFilterResult에 누적
        final newPupilOnly = newUnique.where((e) => HybridLoader.isPupilOnly(e)).toList();
        final existingPupilIds = pupilFilterResult.map((e) => e.id()).toSet();
        final uniquePupilOnly = newPupilOnly.where((e) => !existingPupilIds.contains(e.id())).toList();

        if (uniquePupilOnly.isNotEmpty) {
          pupilFilterResult.addAll(uniquePupilOnly);
        }

        // 일반 모드이거나, Pupil 필터 모드에서 목표 수량(12개 이상)에 도달했으면 루프 종료
        if (!isPupilFilterUsed.value || pupilFilterResult.length >= targetCount) {
          break;
        }
      }

      if (filterController.isPopulationSort) {
        Population.sortByPopulation(queryResult);
        if (isPupilFilterUsed.value) {
          Population.sortByPopulation(pupilFilterResult);
        }
      }

      final hadExistingItems = isPupilFilterUsed.value
          ? pupilFilterResult.isNotEmpty
          : queryResult.isNotEmpty;

      if (isFilterUsed) {
        final target = isPupilFilterUsed.value ? pupilFilterResult : queryResult;
        filterResult = filterController.applyFilter(target);
        searchTotalResultCount.value = baseCount + filterResult.length;
      } else {
        searchTotalResultCount.value = baseCount + (isPupilFilterUsed.value
            ? pupilFilterResult.length
            : queryResult.length);
      }

      reloadForce(isAppend: hadExistingItems);
      ScriptManager.refresh();
    } catch (e, st) {
      Logger.error(
        '[search-error] E: $e\n'
        '$st',
      );
      rethrow;
    } finally {
      isPupilFilterLoading.value = false;
      _querySem.release();
    }
  }

  applyFilter() {
    final target = isPupilFilterUsed.value ? pupilFilterResult : queryResult;
    filterResult = filterController.applyFilter(target);
    isFilterUsed = true;
  }

  doSearch([int targetPosition = 0]) async {
    _queryEnd = false;
    _scrollInProgress = false;
    itemKeys.clear();
    queryResult = [];
    pupilFilterResult = [];

    // targetPosition(점프 위치)를 기반으로 시작 페이지 및 페이지 기준 오프셋 계산 (1-indexed)
    final startPage = (targetPosition ~/ defaultPageSize) + 1;
    final pageBaseOffset = (startPage - 1) * defaultPageSize;
    baseCount = pageBaseOffset;
    final targetIndexInPage = targetPosition - pageBaseOffset;

    pupilFilterPage = startPage;
    mainHybridPage = startPage;

    filterController = FilterController(
      heroKey: 'searchtype${ModalBottomSheetContext.getCount()}',
    );
    isFilterUsed = false;
    searchTotalResultCount.value = baseCount;
    searchPageNum.value = targetIndexInPage;

    // 명시적인 위치 점프(targetPosition > 0)이고 lang:korean + pupil 기능이 켜져 있을 때만 위치를 갱신합니다.
    if (targetPosition > 0 && isPupilFilterUsed.value && isCurrentSearchKorean()) {
      Settings.lastSearchPosition.setValue(targetPosition);
    }

    if (scrollController?.hasClients ?? false) {
      scrollController?.jumpTo(0.0);
    }
    await loadNextQuery();

    if (targetIndexInPage > 0) {
      _scrollToItemIndex(targetIndexInPage);
    }
  }

  void _scrollToItemIndex(int index) {
    void performScroll() {
      if (scrollController == null || !scrollController!.hasClients) return;
      final itemPerRow = [3, 2, 1, 1, 1][Settings.searchResultType.value.index];
      final fallbackHeight = [200.0, 250.0, 130.0, 130.0, 220.0][Settings.searchResultType.value.index];
      final effectiveHeight = _itemHeight > 0.1 ? _itemHeight : fallbackHeight;
      const headerHeight = 76.0;
      final targetRow = index ~/ itemPerRow;
      final targetOffset = index == 0 ? 0.0 : (headerHeight + targetRow * effectiveHeight);
      final maxScroll = scrollController!.position.maxScrollExtent;
      final safeOffset = targetOffset.clamp(0.0, maxScroll > 0 ? maxScroll : targetOffset);
      scrollController!.jumpTo(safeOffset);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      performScroll();
      Future.delayed(const Duration(milliseconds: 100), performScroll);
    });
  }

  Future<void> jumpToLastArticle(BuildContext context) async {
    final targetId = Settings.lastSearchArticleId.value;
    final targetPos = Settings.lastSearchPosition.value;
    final wasPupil = Settings.lastSearchIsPupil.value;

    if (targetId <= 0 && targetPos <= 0) {
      Fluttertoast.showToast(msg: '마지막으로 본 작품 기록이 없습니다.');
      return;
    }

    // 1. 당시 Pupil 필터 상태 복원
    if (wasPupil && !isPupilFilterUsed.value) {
      await togglePupilFilter(context);
    }

    // 2. 현재 메모리에 로드된 리스트에서 타깃 ID 탐색 (0ms 즉시 스크롤)
    final currentList = getSearchList();
    final existingIndex = targetId > 0
        ? currentList.indexWhere((e) => e.id() == targetId)
        : -1;

    if (existingIndex != -1) {
      searchPageNum.value = existingIndex;
      _scrollToItemIndex(existingIndex);
      Fluttertoast.showToast(
        msg: '마지막으로 본 작품(No. $targetId) 위치로 이동했습니다.',
        toastLength: Toast.LENGTH_SHORT,
      );
      return;
    }

    // 3. 아직 로드되지 않았거나 다른 페이지인 경우: 스마트 점프 및 신작 오차 자동 보정
    Fluttertoast.showToast(
      msg: '마지막으로 본 작품(No. $targetId)을 찾는 중...',
      toastLength: Toast.LENGTH_SHORT,
    );

    await doSearch(targetPos);

    // 4. doSearch 후 타깃 작품 위치 탐색
    var foundIndex = targetId > 0
        ? getSearchList().indexWhere((e) => e.id() == targetId)
        : -1;

    // 만약 새 작품이 유입되어 바로 안 보인다면, 다음 배치(최대 3회)를 추가 로드하여 탐색
    int attempts = 0;
    while (foundIndex == -1 && attempts < 3 && !_queryEnd) {
      attempts++;
      await loadNextQuery();
      foundIndex = targetId > 0
          ? getSearchList().indexWhere((e) => e.id() == targetId)
          : -1;
    }

    if (foundIndex != -1) {
      searchPageNum.value = foundIndex;
      _scrollToItemIndex(foundIndex);
      Fluttertoast.showToast(
        msg: '마지막으로 본 작품(No. $targetId) 위치를 찾아 이동했습니다.',
        toastLength: Toast.LENGTH_SHORT,
      );
    } else {
      // 작품 ID를 직접 찾지 못했더라도 저장된 인덱스 위치 근처에 안전하게 도착
      final targetIndexInPage = targetPos - baseCount;
      if (targetIndexInPage > 0 && targetIndexInPage < getSearchList().length) {
        _scrollToItemIndex(targetIndexInPage);
      }
      Fluttertoast.showToast(
        msg: '마지막으로 본 위치($targetPos 번 부근)로 이동했습니다.',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }

  List<QueryResult> getSearchList() {
    if (isFilterUsed) return filterResult;
    if (isPupilFilterUsed.value) return pupilFilterResult;
    return queryResult;
  }

  Future<void> togglePupilFilter(BuildContext context) async {
    if (isPupilFilterLoading.value) return;

    if (isPupilFilterUsed.value) {
      // Pupil 필터 해제 -> 메인 전체 작품 목록으로 0ms 즉시 복원
      isPupilFilterUsed.value = false;
      if (isFilterUsed) {
        filterResult = filterController.applyFilter(queryResult);
        searchTotalResultCount.value = baseCount + filterResult.length;
      } else {
        searchTotalResultCount.value = baseCount + queryResult.length;
      }
      reloadForce();
      Fluttertoast.showToast(
        msg: 'Pupil 필터 해제 (전체 ${queryResult.length}건)',
        toastLength: Toast.LENGTH_SHORT,
      );
      return;
    }

    // Pupil 필터 활성화
    isPupilFilterUsed.value = true;

    // 1) 0ms 즉각 노출: 지금까지 queryResult에 로드된 작품들 중 Pupil 단독작을 즉시 추출
    final cachedPupil = queryResult.where((item) => HybridLoader.isPupilOnly(item)).toList();
    pupilFilterResult = List<QueryResult>.from(cachedPupil);

    if (isFilterUsed) {
      filterResult = filterController.applyFilter(pupilFilterResult);
      searchTotalResultCount.value = baseCount + filterResult.length;
    } else {
      searchTotalResultCount.value = baseCount + pupilFilterResult.length;
    }
    reloadForce();

    // 2) 만약 기존에 캐시된 Pupil 단독작이 스크롤 가능 수량(12개) 미만이라면
    // 화면을 멈추지 않고 비동기로 최소 12개 이상이 채워질 때까지 연속 요청
    if (pupilFilterResult.length < 12 && !_queryEnd) {
      unawaited(loadNextQuery());
    }

    if (pupilFilterResult.isNotEmpty) {
      Fluttertoast.showToast(
        msg: 'Pupil 단독 작품 ${pupilFilterResult.length}건 표시 (스크롤 시 계속 로딩)',
        toastLength: Toast.LENGTH_SHORT,
      );
    } else {
      Fluttertoast.showToast(
        msg: 'Pupil 단독 작품을 찾는 중...',
        toastLength: Toast.LENGTH_SHORT,
      );
    }
  }
}
