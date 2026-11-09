// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/database/query.dart';
import 'package:violet/script/script_manager.dart';

class FirstPageGrouper {
  static final Map<int, String> _firstPageHashMap = <int, String>{};
  static final Map<int, List<QueryResult>> _variantsCache = <int, List<QueryResult>>{};

  /// 작품의 1페이지(표지/첫 페이지) 고유 파일 해시를 가져옵니다.
  /// Hitomi galleryinfo.js의 files[0].hash를 활용하며 메모리 및 세션 캐시에 영구 보관합니다.
  static Future<String?> getFirstPageHash(QueryResult item) async {
    final id = item.id();

    // 1. 메모리 캐시 확인
    if (_firstPageHashMap.containsKey(id)) {
      return _firstPageHashMap[id];
    }
    if (item.result['FirstPageHash'] != null &&
        item.result['FirstPageHash'].toString().isNotEmpty) {
      final hash = item.result['FirstPageHash'].toString();
      _firstPageHashMap[id] = hash;
      return hash;
    }

    // 2. Hitomi galleryinfo로부터 취득
    try {
      final raw = await ScriptManager.getGalleryInfoRaw(id.toString());
      if (raw != null) {
        final jsonText = raw
            .split('var galleryinfo = ')
            .last
            .replaceFirst(RegExp(r';\s*$'), '');
        final info = jsonDecode(jsonText);
        if (info is Map<String, dynamic> &&
            info['files'] is List &&
            (info['files'] as List).isNotEmpty) {
          final firstFile = (info['files'] as List).first;
          if (firstFile is Map && firstFile['hash'] != null) {
            final hash = firstFile['hash'].toString();
            _firstPageHashMap[id] = hash;
            item.result['FirstPageHash'] = hash;
            HybridLoader.cacheMetadata(item);
            return hash;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// 현재 작품과 1페이지(표지) 해시가 일치하거나 동일 작품으로 식별되는 다른 언어/판본 목록을 찾습니다.
  /// 현재 작품을 포함하여 한국어 -> 일본어 -> 영어 -> 기타 언어 순으로 정렬하여 반환합니다.
  static Future<List<QueryResult>> findVariants(QueryResult current) async {
    final currentId = current.id();
    if (_variantsCache.containsKey(currentId)) {
      return _variantsCache[currentId]!;
    }

    final currentHash = await getFirstPageHash(current);
    final variants = <QueryResult>[current];
    final seenIds = <int>{currentId};

    // 현재 작품의 작가 또는 그룹 추출
    final artist = _extractPrimaryTag(current.artists());
    final group = _extractPrimaryTag(current.groups());
    final series = _extractPrimaryTag(current.series());

    List<QueryResult> candidates = [];

    // 작가 -> 그룹 -> 시리즈 순으로 후보 작품 탐색
    if (artist.isNotEmpty && artist.toLowerCase() != 'n/a') {
      candidates = await HybridLoader.fetchArtistArticlesHybrid(
        name: artist,
        type: 'artist',
        pageSize: 40,
      );
    } else if (group.isNotEmpty && group.toLowerCase() != 'n/a') {
      candidates = await HybridLoader.fetchArtistArticlesHybrid(
        name: group,
        type: 'group',
        pageSize: 40,
      );
    } else if (series.isNotEmpty && series.toLowerCase() != 'n/a') {
      candidates = await HybridLoader.fetchArtistArticlesHybrid(
        name: series,
        type: 'series',
        pageSize: 40,
      );
    }

    if (candidates.isNotEmpty) {
      // 1. 제목 매칭 및 유력 후보군 선별 (현재 작품 제외)
      final matchedCandidates = candidates.where((c) {
        if (c.id() == currentId || seenIds.contains(c.id())) return false;
        // 제목 일치 여부 검증
        final titleMatch = HybridLoader.isTitleMatched(
          current.title() ?? '',
          c.title() ?? '',
        );
        return titleMatch;
      }).take(10).toList();

      // 2. 1페이지 해시 정밀 검증
      if (currentHash != null && matchedCandidates.isNotEmpty) {
        await Future.wait(
          matchedCandidates.map((cand) async {
            try {
              final candHash = await getFirstPageHash(cand)
                  .timeout(const Duration(milliseconds: 1500));
              if (candHash != null && candHash == currentHash) {
                if (seenIds.add(cand.id())) {
                  variants.add(cand);
                }
              }
            } catch (_) {}
          }),
        );
      }

      // 3. 만약 1페이지 해시로 매칭되지 않았더라도 제목 토큰이 완벽히 동일하고 언어가 다른 경우 보강
      for (final cand in matchedCandidates) {
        if (!seenIds.contains(cand.id())) {
          final isSameLanguage = HybridLoader.isLanguageMatched(current, cand);
          // 언어가 명확히 다르고 제목이 정확히 일치하는 번역본
          if (!isSameLanguage &&
              HybridLoader.isTitleMatched(current.title() ?? '', cand.title() ?? '')) {
            if (seenIds.add(cand.id())) {
              variants.add(cand);
            }
          }
        }
      }
    }

    // 언어 우선순위 정렬: 한국어 -> 일본어 -> 영어 -> 중국어 -> 기타
    variants.sort((a, b) {
      final rankA = _getLanguageRank(a.language()?.toString() ?? '');
      final rankB = _getLanguageRank(b.language()?.toString() ?? '');
      if (rankA != rankB) return rankA.compareTo(rankB);
      return b.id().compareTo(a.id()); // 최신 ID 우선
    });

    // 모든 발견된 판본들에 대해 캐시 동기화
    for (final v in variants) {
      _variantsCache[v.id()] = variants;
    }

    return variants;
  }

  static String _extractPrimaryTag(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final tokens = raw
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return tokens.isNotEmpty ? tokens.first : '';
  }

  static int _getLanguageRank(String raw) {
    final lang = HybridLoader.normalizeLanguage(raw);
    switch (lang) {
      case 'korean':
        return 1;
      case 'japanese':
        return 2;
      case 'english':
        return 3;
      case 'chinese':
        return 4;
      default:
        return 5;
    }
  }

  /// 캐시 초기화
  static void clearCache() {
    _firstPageHashMap.clear();
    _variantsCache.clear();
  }
}
