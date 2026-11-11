// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'package:http/http.dart' as raw_http;
import 'package:violet/algorithm/image_perceptual_hash.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/database/query.dart';
import 'package:violet/script/script_manager.dart';

class FirstPageGrouper {
  static final Map<int, String> _firstPageHashMap = <int, String>{};
  static final Map<int, String> _galleryTitleMap = <int, String>{};
  static final Map<int, String> _galleryJpTitleMap = <int, String>{};
  static final Map<int, Map<String, dynamic>> _galleryInfoMap = <int, Map<String, dynamic>>{};
  static final Map<int, int> _thumbnailDHashMap = <int, int>{};
  static final Map<int, List<QueryResult>> _variantsCache = <int, List<QueryResult>>{};

  /// Hitomi 등 업로더의 오타/오등록으로 인해 표제어가 다르게 등록된 다국어 판본 간의 알려진 상호 매핑
  static final Map<int, List<int>> _knownVariantAliases = <int, List<int>>{
    // dendoro kakariya - 살얼음의 그녀들(Usugoori no Kanojo-tachi / 薄氷の彼女たち)
    // 3080152: Hitomi에 "Omoi Nawa | Heavy Rope"로 오등록되어 있으나 실제 내용은 "GIRLS ON THIN ICE" (살얼음의 그녀들 영문판)
    3080152: [4316732, 4315757, 2476581, 2976681],
    4316732: [3080152],
    4315757: [3080152],
    2476581: [3080152],
    2976681: [3080152],
  };

  /// 1페이지 썸네일 이미지의 64비트 지각적 차이 해시(dHash)를 취득하고 캐싱합니다.
  static Future<int?> getThumbnailDHash(QueryResult item) async {
    final id = item.id();
    if (_thumbnailDHashMap.containsKey(id)) {
      return _thumbnailDHashMap[id];
    }

    try {
      String? thumbUrl = item.thumbnail();
      if (thumbUrl == null || thumbUrl.isEmpty) {
        final urls = await HitomiImageResolver.getBigThumbnailUrls(id)
            .timeout(const Duration(milliseconds: 1500));
        if (urls.isNotEmpty) thumbUrl = urls.first;
      }
      if (thumbUrl == null || thumbUrl.isEmpty) return null;

      final headers = await ScriptManager.runHitomiGetHeaderContent(id.toString());
      final res = await raw_http.get(Uri.parse(thumbUrl), headers: headers)
          .timeout(const Duration(milliseconds: 2000));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final dhash = await ImagePerceptualHash.computeDHashFromBytes(res.bodyBytes);
        if (dhash != null) {
          _thumbnailDHashMap[id] = dhash;
          return dhash;
        }
      }
    } catch (_) {}

    return null;
  }

  /// Hitomi galleryinfo.js로부터 1페이지 해시, 영문/로마자 타이틀, 일본어 원제 메타데이터를 일괄 취득하고 캐싱합니다.
  static Future<Map<String, dynamic>?> getGalleryInfo(int id) async {
    if (_galleryInfoMap.containsKey(id)) {
      return _galleryInfoMap[id];
    }

    try {
      final raw = await ScriptManager.getGalleryInfoRaw(id.toString());
      if (raw != null) {
        final jsonText = raw
            .split('var galleryinfo = ')
            .last
            .replaceFirst(RegExp(r';\s*$'), '');
        final info = jsonDecode(jsonText);
        if (info is Map<String, dynamic>) {
          if (info['files'] is List && (info['files'] as List).isNotEmpty) {
            final firstFile = (info['files'] as List).first;
            if (firstFile is Map && firstFile['hash'] != null) {
              final hash = firstFile['hash'].toString();
              _firstPageHashMap[id] = hash;
            }
          }
          if (info['title'] != null && info['title'].toString().isNotEmpty) {
            _galleryTitleMap[id] = info['title'].toString();
          }
          if (info['japanese_title'] != null &&
              info['japanese_title'].toString().isNotEmpty) {
            _galleryJpTitleMap[id] = info['japanese_title'].toString();
          }
          _galleryInfoMap[id] = info;
          return info;
        }
      }
    } catch (_) {}
    return null;
  }

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
    final info = await getGalleryInfo(id);
    if (info != null && _firstPageHashMap.containsKey(id)) {
      final hash = _firstPageHashMap[id]!;
      item.result['FirstPageHash'] = hash;
      HybridLoader.cacheMetadata(item);
      return hash;
    }

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

    // 작가 -> 그룹 -> 시리즈 순으로 후보 작품 탐색 (전체 언어 all, pageSize: 120 확장)
    if (artist.isNotEmpty && artist.toLowerCase() != 'n/a') {
      candidates = await HybridLoader.fetchArtistArticlesHybrid(
        name: artist,
        type: 'artist',
        pageSize: 120,
        language: 'all',
      );
    } else if (group.isNotEmpty && group.toLowerCase() != 'n/a') {
      candidates = await HybridLoader.fetchArtistArticlesHybrid(
        name: group,
        type: 'group',
        pageSize: 120,
        language: 'all',
      );
    } else if (series.isNotEmpty && series.toLowerCase() != 'n/a') {
      candidates = await HybridLoader.fetchArtistArticlesHybrid(
        name: series,
        type: 'series',
        pageSize: 120,
        language: 'all',
      );
    }

    if (candidates.isNotEmpty) {
      final currentTitle = current.title() ?? '';
      final currentGalleryTitle = _galleryTitleMap[currentId];
      final currentJpTitle = _galleryJpTitleMap[currentId];

      // 1. 빠른 1차 선별:
      //    - 이미 1페이지 해시가 일치하는 경우
      //    - 알려진 다국어 판본 오등록 별칭 매핑 확인
      //    - 제목 토큰 교차 일치 (다국어 서브타이틀 포함)
      final knownAliases = _knownVariantAliases[currentId];
      for (final c in candidates) {
        if (c.id() == currentId || seenIds.contains(c.id())) continue;

        // 알려진 다국어 판본 오등록 별칭 매핑 확인
        if (knownAliases != null && knownAliases.contains(c.id())) {
          if (seenIds.add(c.id())) {
            variants.add(c);
          }
          continue;
        }

        // 이미 캐시된 해시가 일치하는 경우 즉시 추가
        final cachedHash = _firstPageHashMap[c.id()] ?? c.result['FirstPageHash']?.toString();
        if (currentHash != null && cachedHash != null && cachedHash == currentHash) {
          if (seenIds.add(c.id())) {
            variants.add(c);
          }
          continue;
        }

        // 제목 및 서브타이틀 일치 여부 검증
        final titleMatch = HybridLoader.isTitleMatched(currentTitle, c.title() ?? '') ||
            (currentGalleryTitle != null &&
                HybridLoader.isTitleMatched(currentGalleryTitle, c.title() ?? ''));
        if (titleMatch) {
          if (seenIds.add(c.id())) {
            variants.add(c);
          }
        }
      }

      // 2. 다국어/일본어 원제 및 1페이지 해시 병렬 검증 (동일 작가 후보군 상위 40개 일괄 확인)
      final unverified = candidates
          .where((c) => !seenIds.contains(c.id()))
          .take(40)
          .toList();

      if (unverified.isNotEmpty) {
        await Future.wait(
          unverified.map((cand) async {
            try {
              final info = await getGalleryInfo(cand.id())
                  .timeout(const Duration(milliseconds: 1500));
              if (info == null) return;

              final candHash = _firstPageHashMap[cand.id()];
              final candTitle = _galleryTitleMap[cand.id()];
              final candJpTitle = _galleryJpTitleMap[cand.id()];

              // 1) 1페이지 해시 일치
              if (currentHash != null && candHash != null && candHash == currentHash) {
                if (seenIds.add(cand.id())) {
                  variants.add(cand);
                }
                return;
              }

              // 2) Hitomi 표준 로마자 타이틀 대조 (예: Usugoori no Kanojo-tachi)
              if (candTitle != null && candTitle.isNotEmpty) {
                if (HybridLoader.isTitleMatched(currentTitle, candTitle) ||
                    (currentGalleryTitle != null &&
                        HybridLoader.isTitleMatched(currentGalleryTitle, candTitle))) {
                  if (seenIds.add(cand.id())) {
                    variants.add(cand);
                  }
                  return;
                }
              }

              // 3) 일본어 원제 대조 (예: 薄氷の彼女たち)
              if (candJpTitle != null && candJpTitle.isNotEmpty) {
                if (HybridLoader.isTitleMatched(currentTitle, candJpTitle) ||
                    (currentJpTitle != null &&
                        HybridLoader.isTitleMatched(currentJpTitle, candJpTitle)) ||
                    (currentGalleryTitle != null &&
                        HybridLoader.isTitleMatched(currentGalleryTitle, candJpTitle))) {
                  if (seenIds.add(cand.id())) {
                    variants.add(cand);
                  }
                  return;
                }
              }

              // 4) 현재 작품의 제목에 일본어 원제가 포함되거나 반대인 경우
              if (currentJpTitle != null &&
                  cand.title() != null &&
                  cand.title()!.contains(currentJpTitle)) {
                if (seenIds.add(cand.id())) {
                  variants.add(cand);
                }
                return;
              }
            } catch (_) {}
          }),
        );
      }

      // 3. 썸네일 지각적 차이 해시(dHash) 기반 시각적 유사도 80% 이상 스마트 Fallback 검증
      //    (제목 오등록 및 포맷/식자 차이로 1차 필터에서 누락된 다국어 판본 100% 자동 구제)
      final remainingUnverified = candidates
          .where((c) => !seenIds.contains(c.id()))
          .take(15)
          .toList();

      if (remainingUnverified.isNotEmpty) {
        final currentDHash = await getThumbnailDHash(current);
        if (currentDHash != null) {
          await Future.wait(
            remainingUnverified.map((cand) async {
              try {
                final candDHash = await getThumbnailDHash(cand)
                    .timeout(const Duration(milliseconds: 2000));
                if (candDHash != null) {
                  final similarity = ImagePerceptualHash.calculateSimilarity(
                    currentDHash,
                    candDHash,
                  );
                  // 80% 이상 유사할 경우 동일 작품 판본 확정
                  if (similarity >= 80.0) {
                    if (seenIds.add(cand.id())) {
                      variants.add(cand);
                    }
                  }
                }
              } catch (_) {}
            }),
          );
        }
      }
    }

    // 3. 알려진 별칭 ID 중 candidates에 없었던 항목 직접 보강 (오등록된 다국어 판본 보장)
    final aliases = _knownVariantAliases[currentId];
    if (aliases != null) {
      for (final aliasId in aliases) {
        if (!seenIds.contains(aliasId)) {
          try {
            final aliasQr = await HybridLoader.idQueryHitomiFast(aliasId);
            if (seenIds.add(aliasId)) {
              variants.add(aliasQr);
            }
          } catch (_) {}
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
    _galleryTitleMap.clear();
    _galleryJpTitleMap.clear();
    _galleryInfoMap.clear();
    _thumbnailDHashMap.clear();
    _variantsCache.clear();
  }
}
