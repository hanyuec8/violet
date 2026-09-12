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

  final VoidCallback reloadForce;

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
    const searchBarHeight = 64 + 16;
    final curI =
        ((scrollController!.offset - searchBarHeight) / _itemHeight + 1)
            .toInt() *
        itemPerRow;

    if (curI != searchPageNum.value && isExtended.value) {
      searchPageNum.value = curI;
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
          pageSize: 25,
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

      if (isFilterUsed) {
        final target = isPupilFilterUsed.value ? pupilFilterResult : queryResult;
        filterResult = filterController.applyFilter(target);
        searchTotalResultCount.value = filterResult.length;
      } else {
        searchTotalResultCount.value = isPupilFilterUsed.value
            ? pupilFilterResult.length
            : queryResult.length;
      }

      reloadForce();
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

  doSearch([int baseCount = 0]) async {
    this.baseCount = baseCount;
    _queryEnd = false;
    queryResult = [];
    pupilFilterResult = [];
    pupilFilterPage = 1;
    mainHybridPage = 1;
    filterController = FilterController(
      heroKey: 'searchtype${ModalBottomSheetContext.getCount()}',
    );
    isFilterUsed = false;
    searchTotalResultCount.value = 0;
    searchPageNum.value = 0;
    if (scrollController?.hasClients ?? false) {
      scrollController?.jumpTo(0.0);
    }
    loadNextQuery();
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
        searchTotalResultCount.value = filterResult.length;
      } else {
        searchTotalResultCount.value = queryResult.length;
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
      searchTotalResultCount.value = filterResult.length;
    } else {
      searchTotalResultCount.value = pupilFilterResult.length;
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
