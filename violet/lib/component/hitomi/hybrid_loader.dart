// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:async';
import 'dart:convert';
import 'package:violet/component/hentai.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/component/hitomi/hitomi_parser.dart';
import 'package:violet/component/hitomi/population.dart';
import 'package:violet/component/query_translate.dart';
import 'package:violet/database/database.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/database/user/user.dart';
import 'package:violet/log/log.dart';
import 'package:violet/network/wrapper.dart' as http;
import 'package:violet/script/script_manager.dart';
import 'package:violet/settings/settings.dart';

/// Violet (E-Hentai / 로컬 DB) + Pupil (Hitomi Nozomi Range Request)
/// 하이브리드 작품 로더
class HybridLoader {
  /// 사용자가 설정한 검색 대상 언어 목록 (비어있으면 전체)
  static List<String> getSelectedLanguages() {
    final inc = Settings.includeTags.value.toLowerCase();
    final langs = <String>[];
    if (inc.contains('korean')) langs.add('korean');
    if (inc.contains('japanese')) langs.add('japanese');
    if (inc.contains('english')) langs.add('english');
    if (inc.contains('chinese')) langs.add('chinese');
    return langs;
  }

  /// 앱 실행 중 유지되는 인메모리 세션 캐시 (앱 종료 시 자동 소멸)
  /// 품번(Id) -> 뱃지 소스 ('common' | 'pupil' | 'violet' | 'pupil_only')
  static final Map<int, String> _sessionBadgeCache = <int, String>{};

  /// 품번(Id) -> Hitomi 기본 메타데이터 QueryResult
  static final Map<int, QueryResult> _sessionMetadataCache = <int, QueryResult>{};

  /// 작가, 그룹, 시리즈, 캐릭터, 업로더의 최신 작품 목록을
  /// Hitomi Nozomi와 E-Hentai에서 동시에 비동기 수집하여 중복 제거 후 반환합니다.
  static Future<List<QueryResult>> fetchArtistArticlesHybrid({
    required String name,
    required String type,
    int page = 1,
    int pageSize = 60,
    String? language,
  }) async {
    final selectedLangs = getSelectedLanguages();
    String targetLang = language ?? (selectedLangs.length == 1 ? selectedLangs.first : 'all');

    String getNozomiUrl(String lang) {
      switch (type.toLowerCase()) {
        case 'artist':
          return HitomiNozomi.getArtistIndexUrl(name, lang);
        case 'group':
          return HitomiNozomi.getGroupIndexUrl(name, lang);
        case 'series':
          return HitomiNozomi.getSeriesIndexUrl(name, lang);
        case 'character':
          return HitomiNozomi.getCharacterIndexUrl(name, lang);
        case 'uploader':
          return HitomiNozomi.getUploaderIndexUrl(name, lang);
        case 'tag':
          return HitomiNozomi.getTagIndexUrl(name, lang);
        default:
          return HitomiNozomi.getArtistIndexUrl(name, lang);
      }
    }

    Future<List<QueryResult>> fetchWithLang(String lang) async {
      final results = <QueryResult>[];
      final seenIds = <int>{};

      // 1) 로컬 SQLite DB (HitomiColumnModel) 스트림: 0.05초 만에 즉시 반환
      final localDbFuture = Future<List<QueryResult>>(() async {
        try {
          final db = await DataBaseManager.getInstance();
          if (db.db == null || !db.db!.isOpen) return [];

          final safeName = name.replaceAll("'", "''").replaceAll(' ', '_');
          final token = '${type.toLowerCase()}:$safeName';
          final langToken = lang != 'all' ? 'language:$lang' : '';
          final translated = translate2query('$token $langToken'.trim());
          final offset = (page - 1) * pageSize;
          final sql = '$translated ORDER BY Id DESC LIMIT $pageSize OFFSET $offset';

          final rows = await db.query(sql);
          return rows.map((r) {
            final map = Map<String, dynamic>.from(r);
            map['source'] = 'common';
            map['is_common'] = true;
            return QueryResult(result: map);
          }).toList();
        } catch (e, st) {
          Logger.error('[HybridLoader-Artist-Db] E: $e\n$st');
          return [];
        }
      }).timeout(
        const Duration(seconds: 4),
        onTimeout: () => <QueryResult>[],
      );

      // 2) Hitomi Nozomi Range Request 스트림 (Pupil 방식)
      final hitomiFuture = Future<List<QueryResult>>(() async {
        final hitomiList = <QueryResult>[];
        try {
          List<int> ids = [];
          if (lang != 'all') {
            ids = await HitomiNozomi.fetchGalleryIds(
              getNozomiUrl(lang),
              page,
              pageSize: pageSize,
            );
          } else {
            ids = await HitomiNozomi.fetchGalleryIds(
              getNozomiUrl('all'),
              page,
              pageSize: pageSize,
            );
          }
          if (ids.isEmpty) return [];

          // 1단계: 캐시(메모리 + user.db ArticleCache 디스크) 일괄 선조회 (0.01초)
          final cachedMap = await getCachedMetadataBatch(ids);
          final missingIds = <int>[];
          for (final id in ids) {
            if (cachedMap.containsKey(id)) {
              hitomiList.add(cachedMap[id]!);
            } else {
              missingIds.add(id);
            }
          }

          // 2단계: 캐시에 없는 항목만 경량 네트워크 조회 (_idQueryHitomiFast)
          if (missingIds.isNotEmpty) {
            const chunkSize = 20;
            for (var i = 0; i < missingIds.length; i += chunkSize) {
              final end = (i + chunkSize < missingIds.length) ? i + chunkSize : missingIds.length;
              final chunk = missingIds.sublist(i, end);
              final chunkFutures = chunk.map((id) => _idQueryHitomiFast(id));
              hitomiList.addAll(await Future.wait(chunkFutures));
            }
          }
          for (final qr in hitomiList) {
            qr.result['source'] = 'pupil';
          }
          return hitomiList;
        } catch (e, st) {
          Logger.error('[HybridLoader-Artist-Hitomi] E: $e\n$st');
          return hitomiList;
        }
      }).timeout(
        const Duration(seconds: 12),
        onTimeout: () => <QueryResult>[],
      );

      // 3) E-Hentai 검색 (Violet 웹 검색 방식)
      final ehentaiFuture = Future<List<QueryResult>>(() async {
        try {
          final langPrefix = lang != 'all' ? 'language:$lang ' : '';
          final queryTag = '$langPrefix${type.toLowerCase()}:"$name"';
          final ehQuery = formatEHentaiQuery(queryTag, lang);
          final offset = (page - 1) * pageSize;
          final ehList = await HentaiManager.searchEHentai(ehQuery, offset);
          for (final qr in ehList) {
            qr.result['source'] = 'violet';
          }
          return ehList;
        } catch (e, st) {
          Logger.error('[HybridLoader-Artist-EHentai] E: $e\n$st');
          return [];
        }
      }).timeout(
        const Duration(seconds: 10),
        onTimeout: () => <QueryResult>[],
      );

      // 3개 소스를 병렬로 동시 대기 (Triple Hybrid)
      final responses = await Future.wait([localDbFuture, hitomiFuture, ehentaiFuture])
          .timeout(
            const Duration(seconds: 14),
            onTimeout: () => [<QueryResult>[], <QueryResult>[], <QueryResult>[]],
          );
      final localDbResults = responses[0];
      final hitomiResults = responses[1];
      final ehResults = responses[2];

      void addResult(QueryResult qr) {
        final id = qr.id();

        // 언어 필터링 (한국어 등 지정 언어가 설정된 경우)
        if (lang != 'all') {
          final qrLang = (qr.language() ?? '').toString().toLowerCase();
          final tags = (qr.tags() ?? '').toString().toLowerCase();
          final qrTitle = (qr.title() ?? '').toString().toLowerCase();

          final matchLang = qrLang.contains(lang) ||
              tags.contains(lang) ||
              (lang == 'korean' &&
                  (qrLang == 'korean' ||
                      tags.contains('korean') ||
                      qrTitle.contains('[한국어]') ||
                      qrTitle.contains('(한국어)')));

          if (!matchLang) {
            return;
          }
        }

        if (seenIds.contains(id)) return;
        seenIds.add(id);
        results.add(qr);
      }

      // 로컬 DB 결과 우선 반영 (Violet 공식 DB 100% 공통 작품)
      for (final item in localDbResults) {
        addResult(item);
      }

      // Hitomi 최신 결과 반영 (로컬 DB와 대조 및 승격)
      for (final item in hitomiResults) {
        final id = item.id();
        final existing = results.where((r) => r.id() == id).firstOrNull;
        if (existing != null) {
          existing.result['source'] = 'common';
          existing.result['is_common'] = true;
          _sessionBadgeCache[id] = 'common';
        } else {
          // 로컬 DB에 동일 언어 및 제목이 일치하는 항목이 있으면 common으로 승격
          final existingByTitle = results.where((r) =>
              isLanguageMatched(r, item) &&
              isTitleMatched(r.title() ?? '', item.title() ?? '')).firstOrNull;
          if (existingByTitle != null) {
            existingByTitle.result['source'] = 'common';
            existingByTitle.result['is_common'] = true;
            _sessionBadgeCache[existingByTitle.id()] = 'common';
          }
          // 중요: Hitomi의 고유 ID 작품은 절대로 버리지 않고 리스트에 독립 추가
          addResult(item);
        }
      }

      // E-Hentai 결과 추가 병합 및 공통 작품 승격
      for (final item in ehResults) {
        final id = item.id();
        final itemTitle = item.title() ?? '';
        final existing = results.where((r) {
          if (r.id() == id) return true;
          return isLanguageMatched(r, item) && isTitleMatched(r.title() ?? '', itemTitle);
        }).firstOrNull;

        if (existing != null) {
          existing.result['source'] = 'common';
          existing.result['is_common'] = true;
          if (item.ehash() != null) existing.result['EHash'] = item.ehash();
          _sessionBadgeCache[existing.id()] = 'common';
        } else {
          addResult(item);
        }
      }

      // ID 기준 최신순 정렬
      results.sort((a, b) => b.id().compareTo(a.id()));
      return results;
    }

    // 사용자가 지정한 targetLang으로 검색 (지정 언어 부재 시 타 언어를 임의로 섞지 않음)
    var finalResults = await fetchWithLang(targetLang);

    return finalResults;
  }

  /// 제목 정규화 유틸리티 (특수문자, 괄호, 이벤트명, 언어태그 제거)
  static String normalizeTitle(String raw) {
    var s = raw
        .replaceAll(RegExp(r'\[.*?\]'), ' ')
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .replaceAll(RegExp(r'\{.*?\}'), ' ')
        .toLowerCase();
    // 한글, 영문, 일본어(가나/한자), 숫자만 남겨 정밀 비교
    return s.replaceAll(RegExp(r'[^0-9a-zA-Z가-힣\u3040-\u30ff\u4e00-\u9faf]'), '');
  }

  /// 제목에서 서브타이틀(|, /, :) 등을 고려하여 정규화된 토큰 목록을 추출합니다.
  static List<String> extractTitleTokens(String raw) {
    if (raw.trim().isEmpty) return [];
    final results = <String>{};

    // 1. 파이프(|), 슬래시(/), 하이픈(-) 등 서브타이틀 분리자로 분할
    final parts = raw.split(RegExp(r'\||\/|\s-\s'));
    for (final part in parts) {
      final norm = normalizeTitle(part);
      if (norm.length >= 3) {
        results.add(norm);
      }
    }

    // 2. 전체 문자열 정규화
    final fullNorm = normalizeTitle(raw);
    if (fullNorm.length >= 3) {
      results.add(fullNorm);
    }

    return results.toList();
  }

  /// 두 제목이 동일하거나 동일 작품의 변형인지 정밀 대조합니다.
  static bool isTitleMatched(String rawA, String rawB) {
    if (rawA.isEmpty || rawB.isEmpty) return false;
    final tokensA = extractTitleTokens(rawA);
    final tokensB = extractTitleTokens(rawB);

    for (final a in tokensA) {
      for (final b in tokensB) {
        if (a == b) return true;
        if (a.length >= 5 && b.length >= 5) {
          if (a.contains(b) || b.contains(a)) return true;
        }
      }
    }
    return false;
  }

  /// 두 작품의 언어가 일치하는지 판별합니다.
  /// 둘 중 하나가 언어 미지정이거나 N/A인 경우 허용하며, 명확한 언어가 서로 다르면 false를 반환합니다.
  static bool isLanguageMatched(QueryResult a, QueryResult b) {
    final langA = normalizeLanguage(a.language()?.toString() ?? '');
    final langB = normalizeLanguage(b.language()?.toString() ?? '');
    if (langA.isEmpty || langA == 'n/a' || langB.isEmpty || langB == 'n/a') {
      return true;
    }
    return langA == langB;
  }

  /// 언어 문자열을 표준화 (korean, japanese, english, chinese, spanish 등)
  static String normalizeLanguage(String raw) {
    final l = raw.toLowerCase().trim();
    if (l.contains('korean') || l.contains('한국어')) return 'korean';
    if (l.contains('japanese') || l.contains('일본어') || l.contains('日本語')) return 'japanese';
    if (l.contains('english') || l.contains('영어')) return 'english';
    if (l.contains('chinese') || l.contains('중국어') || l.contains('中文')) return 'chinese';
    if (l.contains('spanish') || l.contains('español') || l.contains('스페인어')) return 'spanish';
    return l;
  }

  /// 사용자가 입력한 다양한 검색어(태그, 작가, 그룹, 시리즈, 캐릭터, 업로더 또는 성별 없는 태그)를
  /// Hitomi Nozomi 인덱스 URL로 스마트하게 변환하여 Gallery ID 목록을 Range Header로 로딩합니다.
  /// random 검색 시 최신작뿐만 아니라 10년 전 고전부터 최근까지 전 기간(0~100%)에서
  /// 균등 분산 무작위 샘플링으로 Gallery ID 목록을 수집합니다.
  static Future<List<int>> fetchRandomGalleryIdsForQuery({
    required String query,
    required String targetLang,
    required List<String> selectedLangs,
    required int count,
    required double? seed,
    required int page,
  }) async {
    try {
      String targetUrl;
      final cleanQuery = query.trim();
      if (cleanQuery.isEmpty) {
        if (targetLang != 'all') {
          targetUrl = HitomiNozomi.getLanguageIndexUrl(targetLang);
        } else if (selectedLangs.isNotEmpty && !selectedLangs.contains('all')) {
          targetUrl = HitomiNozomi.getLanguageIndexUrl(selectedLangs.first);
        } else {
          targetUrl = HitomiNozomi.getIndexAllUrl();
        }
      } else {
        final tokens = cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
        final langToken = tokens.where((t) => t.startsWith('lang:') || t.startsWith('language:')).firstOrNull;
        final nonLang = tokens.where((t) => !t.startsWith('lang:') && !t.startsWith('language:')).toList();
        if (nonLang.isEmpty && langToken != null) {
          final l = langToken.split(':').last;
          targetUrl = HitomiNozomi.getLanguageIndexUrl(l);
        } else {
          return await fetchGalleryIdsForQuery(
            query: cleanQuery,
            page: page,
            pageSize: count,
            targetLang: targetLang,
          );
        }
      }

      final totalCount = await HitomiNozomi.getTotalCount(targetUrl);
      if (totalCount == null || totalCount <= count) {
        return await fetchGalleryIdsForQuery(
          query: cleanQuery,
          page: page,
          pageSize: count,
          targetLang: targetLang,
        );
      }

      const numSegments = 5;
      final perSegment = (count / numSegments).ceil();
      final segmentSize = totalCount ~/ numSegments;
      final s = seed ?? (DateTime.now().microsecondsSinceEpoch % 10000) / 1000.0 + 1.0;

      final futures = <Future<List<int>>>[];
      for (int i = 0; i < numSegments; i++) {
        final segStart = i * segmentSize;
        final maxOffsetInSeg = (segmentSize - perSegment).clamp(1, segmentSize);
        final segOffset = ((s * 10000 + page * 499 + i * 173).toInt() % maxOffsetInSeg);
        final absOffset = (segStart + segOffset).clamp(0, totalCount - perSegment);
        futures.add(HitomiNozomi.fetchGalleryIdsByOffset(targetUrl, absOffset, perSegment));
      }

      final results = await Future.wait(futures);
      final mergedIds = <int>{};
      for (final list in results) {
        mergedIds.addAll(list);
      }

      return mergedIds.take(count).toList();
    } catch (e, st) {
      Logger.error('[HybridLoader-RandomFetch] E: $e\n$st');
      return await fetchGalleryIdsForQuery(
        query: query,
        page: page,
        pageSize: count,
        targetLang: targetLang,
      );
    }
  }

  static Future<List<int>> fetchGalleryIdsForQuery({
    required String query,
    required int page,
    int pageSize = 30,
    required String targetLang,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      if (targetLang != 'all') {
        final ids = await HitomiNozomi.fetchGalleryIds(
          HitomiNozomi.getLanguageIndexUrl(targetLang),
          page,
          pageSize: pageSize,
        );
        if (ids.isNotEmpty) return ids;
      }
      return await HitomiNozomi.fetchGalleryIds(
        HitomiNozomi.getIndexAllUrl(),
        page,
        pageSize: pageSize,
      );
    }

    // 복합 쿼리의 경우 토큰 추출 및 언어 토큰 감지
    final tokens =
        cleanQuery.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

    String effectiveLang = targetLang;
    String? explicitLang;
    final nonLangTokens = <String>[];

    for (final token in tokens) {
      final lower = token.toLowerCase();
      if (lower.startsWith('lang:')) {
        explicitLang = lower.substring(5).trim();
      } else if (lower.startsWith('language:')) {
        explicitLang = lower.substring(9).trim();
      } else {
        nonLangTokens.add(token);
      }
    }

    if (explicitLang != null && explicitLang.isNotEmpty) {
      effectiveLang = explicitLang;
    }

    // 언어 토큰만 있는 단독 쿼리인 경우 (예: 'lang:korean' 또는 'language:japanese')
    if (nonLangTokens.isEmpty && explicitLang != null && explicitLang.isNotEmpty) {
      return await HitomiNozomi.fetchGalleryIds(
        HitomiNozomi.getLanguageIndexUrl(explicitLang),
        page,
        pageSize: pageSize,
      );
    }

    var primaryTerm = nonLangTokens.isNotEmpty
        ? nonLangTokens.first
        : (tokens.isNotEmpty ? tokens.first : cleanQuery);
    if (primaryTerm.toLowerCase().startsWith('tag:')) {
      primaryTerm = primaryTerm.substring(4).trim();
    }

    // 순수 숫자 또는 id:12345 인 경우 품번 ID 직접 반환
    final numericId = int.tryParse(primaryTerm) ??
        (primaryTerm.toLowerCase().startsWith('id:')
            ? int.tryParse(primaryTerm.substring(3).trim())
            : null);
    if (numericId != null) {
      return page == 1 ? [numericId] : <int>[];
    }

    final colonIdx = primaryTerm.indexOf(':');
    if (colonIdx != -1) {
      final prefix = primaryTerm.substring(0, colonIdx).trim().toLowerCase();
      final val = primaryTerm.substring(colonIdx + 1).trim();
      switch (prefix) {
        case 'lang':
        case 'language':
          return await HitomiNozomi.fetchGalleryIds(
            HitomiNozomi.getLanguageIndexUrl(val.toLowerCase()),
            page,
            pageSize: pageSize,
          );
        case 'artist':
          if (effectiveLang != 'all') {
            final ids = await HitomiNozomi.fetchGalleryIds(
              HitomiNozomi.getArtistIndexUrl(val, effectiveLang),
              page,
              pageSize: pageSize,
            );
            if (ids.isNotEmpty) return ids;
            if (explicitLang != null && explicitLang.isNotEmpty) return [];
          }
          return await HitomiNozomi.fetchGalleryIds(
            HitomiNozomi.getArtistIndexUrl(val, 'all'),
            page,
            pageSize: pageSize,
          );
        case 'group':
          if (effectiveLang != 'all') {
            final ids = await HitomiNozomi.fetchGalleryIds(
              HitomiNozomi.getGroupIndexUrl(val, effectiveLang),
              page,
              pageSize: pageSize,
            );
            if (ids.isNotEmpty) return ids;
            if (explicitLang != null && explicitLang.isNotEmpty) return [];
          }
          return await HitomiNozomi.fetchGalleryIds(
            HitomiNozomi.getGroupIndexUrl(val, 'all'),
            page,
            pageSize: pageSize,
          );
        case 'series':
          if (effectiveLang != 'all') {
            final ids = await HitomiNozomi.fetchGalleryIds(
              HitomiNozomi.getSeriesIndexUrl(val, effectiveLang),
              page,
              pageSize: pageSize,
            );
            if (ids.isNotEmpty) return ids;
            if (explicitLang != null && explicitLang.isNotEmpty) return [];
          }
          return await HitomiNozomi.fetchGalleryIds(
            HitomiNozomi.getSeriesIndexUrl(val, 'all'),
            page,
            pageSize: pageSize,
          );
        case 'character':
          if (effectiveLang != 'all') {
            final ids = await HitomiNozomi.fetchGalleryIds(
              HitomiNozomi.getCharacterIndexUrl(val, effectiveLang),
              page,
              pageSize: pageSize,
            );
            if (ids.isNotEmpty) return ids;
            if (explicitLang != null && explicitLang.isNotEmpty) return [];
          }
          return await HitomiNozomi.fetchGalleryIds(
            HitomiNozomi.getCharacterIndexUrl(val, 'all'),
            page,
            pageSize: pageSize,
          );
        case 'uploader':
          if (effectiveLang != 'all') {
            final ids = await HitomiNozomi.fetchGalleryIds(
              HitomiNozomi.getUploaderIndexUrl(val, effectiveLang),
              page,
              pageSize: pageSize,
            );
            if (ids.isNotEmpty) return ids;
            if (explicitLang != null && explicitLang.isNotEmpty) return [];
          }
          return await HitomiNozomi.fetchGalleryIds(
            HitomiNozomi.getUploaderIndexUrl(val, 'all'),
            page,
            pageSize: pageSize,
          );
        case 'tag':
        case 'female':
        case 'male':
          if (effectiveLang != 'all') {
            final ids = await HitomiNozomi.fetchTagGalleryIds(
              primaryTerm,
              page,
              pageSize: pageSize,
              language: effectiveLang,
            );
            if (ids.isNotEmpty) return ids;
            if (explicitLang != null && explicitLang.isNotEmpty) return [];
          }
          return await HitomiNozomi.fetchTagGalleryIds(
            primaryTerm,
            page,
            pageSize: pageSize,
            language: 'all',
          );
        default:
          break;
      }
    }

    // 콜론이 없는 일반 단어: 태그 -> 작가 -> 시리즈 순 스마트 조회
    if (effectiveLang != 'all') {
      final tagIds = await HitomiNozomi.fetchTagGalleryIds(
        primaryTerm,
        page,
        pageSize: pageSize,
        language: effectiveLang,
      );
      if (tagIds.isNotEmpty) return tagIds;
    }
    final tagIdsAll = await HitomiNozomi.fetchTagGalleryIds(
      primaryTerm,
      page,
      pageSize: pageSize,
      language: 'all',
    );
    if (tagIdsAll.isNotEmpty) return tagIdsAll;

    final artistIds = await HitomiNozomi.fetchGalleryIds(
      HitomiNozomi.getArtistIndexUrl(
        primaryTerm,
        effectiveLang != 'all' ? effectiveLang : 'all',
      ),
      page,
      pageSize: pageSize,
    );
    if (artistIds.isNotEmpty) return artistIds;

    return await HitomiNozomi.fetchGalleryIds(
      HitomiNozomi.getSeriesIndexUrl(
        primaryTerm,
        effectiveLang != 'all' ? effectiveLang : 'all',
      ),
      page,
      pageSize: pageSize,
    );
  }

  /// E-Hentai 검색 쿼리 정규화 (언더스코어를 공백으로 변환 및 lang -> language 변환)
  static String formatEHentaiQuery(String cleanQuery, String targetLang) {
    var q = cleanQuery
        .replaceAll(RegExp(r'\blang:', caseSensitive: false), 'language:')
        .replaceAll('_', ' ')
        .trim();
    if (q.toLowerCase().contains('language:')) {
      // 이미 쿼리에 language 태그가 명시되어 있다면 추가 prefix 없이 그대로 사용
      return q;
    }
    if (targetLang == 'all') return q;
    final langPrefix = 'language:$targetLang';
    return q.isEmpty ? langPrefix : '$langPrefix $q';
  }

  /// Hitomi에서 수집된 작품 목록에 대해 로컬 DB, 북마크 DB, E-Hentai 대조군을 종합 검증하여
  /// 기존 Violet/E-Hentai에 존재하는 작품은 'common'으로 확정 승격하고,
  /// 오직 어디에도 존재하지 않는 순수 Hitomi 독점작만 'pupil_only'로 확정합니다.
  static Future<void> verifyAndTagPupilArticles(
    List<QueryResult> items, {
    Set<int>? knownEhIds,
    Set<String>? knownEhTitles,
  }) async {
    if (items.isEmpty) return;

    final idListStr = items.map((e) => e.id()).join(',');

    // 1) 로컬 DB(HitomiColumnModel) ID 및 제목 매칭
    try {
      final db = await DataBaseManager.getInstance();
      if (db.db != null && db.db!.isOpen && idListStr.isNotEmpty) {
        // ID 매칭
        final dbMatches = await db.query(
          'SELECT Id, Title, EHash FROM HitomiColumnModel WHERE Id IN ($idListStr)',
        );
        for (final row in dbMatches) {
          final rid = row['Id'] as int?;
          if (rid != null) {
            for (final item in items) {
              if (item.id() == rid) {
                item.result['source'] = 'common';
                item.result['is_common'] = true;
                if (row['EHash'] != null) item.result['EHash'] = row['EHash'];
                _sessionBadgeCache[rid] = 'common';
              }
            }
          }
        }

        // 제목 기반 매칭 (아직 common이 아닌 항목)
        for (final item in items) {
          if (item.result['is_common'] == true) continue;
          final tokens = extractTitleTokens(item.title() ?? '');
          for (final tok in tokens) {
            if (tok.length < 4) continue;
            final safeTok = tok.replaceAll("'", "''");
            try {
              final matches = await db.query(
                "SELECT Id, Title, EHash FROM HitomiColumnModel WHERE Title LIKE '%$safeTok%' LIMIT 3",
              );
              for (final mRow in matches) {
                final dbTitle = mRow['Title'] as String? ?? '';
                if (isTitleMatched(item.title() ?? '', dbTitle)) {
                  item.result['source'] = 'common';
                  item.result['is_common'] = true;
                  if (mRow['EHash'] != null) item.result['EHash'] = mRow['EHash'];
                  _sessionBadgeCache[item.id()] = 'common';
                  break;
                }
              }
            } catch (_) {}
            if (item.result['is_common'] == true) break;
          }
        }
      }
    } catch (_) {}

    // 2) 북마크 DB(user.db) 대조: 사용자의 북마크에 있는 작품은 공통(common)으로 확정
    try {
      final bookmark = await Bookmark.getInstance();
      for (final item in items) {
        if (item.result['is_common'] == true) continue;
        if (await bookmark.isBookmark(item.id())) {
          item.result['source'] = 'common';
          item.result['is_common'] = true;
          _sessionBadgeCache[item.id()] = 'common';
        }
      }
    } catch (_) {}

    // 3) 외부에서 전달된 E-Hentai 대조군(knownEhIds, knownEhTitles) 확인
    if (knownEhIds != null || knownEhTitles != null) {
      for (final item in items) {
        if (item.result['is_common'] == true) continue;
        if (knownEhIds != null && knownEhIds.contains(item.id())) {
          item.result['source'] = 'common';
          item.result['is_common'] = true;
          _sessionBadgeCache[item.id()] = 'common';
          continue;
        }
        if (knownEhTitles != null && knownEhTitles.isNotEmpty) {
          final iTitle = item.title() ?? '';
          for (final ehTitle in knownEhTitles) {
            if (isTitleMatched(iTitle, ehTitle)) {
              item.result['source'] = 'common';
              item.result['is_common'] = true;
              _sessionBadgeCache[item.id()] = 'common';
              break;
            }
          }
        }
      }
    }

    // 4) 철저한 검증 후 판정 확정: 어디에도 속하지 않는 순수 Hitomi 독점작만 pupil_only
    for (final item in items) {
      if (item.result['is_common'] == true ||
          item.result['source'] == 'common' ||
          item.result['source'] == 'violet' ||
          item.ehash() != null) {
        item.result['source'] = 'common';
        item.result['is_common'] = true;
        _sessionBadgeCache[item.id()] = 'common';
      } else {
        item.result['source'] = 'pupil_only';
        item.result['is_pupil_only'] = true;
        _sessionBadgeCache[item.id()] = 'pupil_only';
      }
    }
  }

  /// Violet 웹 방식(E-Hentai)과 Pupil 방식(Hitomi) 둘 다에서 보이는 공통 작품은 철저히 제외하고,
  /// 오직 Pupil 방식으로만 불러올 수 있는 순수 독점/단독 최신 작품만 필터링하여 반환합니다.
  /// 공통 작품으로 인해 이번 페이지 결과가 비어있더라도, Hitomi 인덱스가 남아있는 한
  /// 연속 탐색하여 최소한의 독점 작품을 확보한 뒤 반환합니다.
  static Future<({List<QueryResult> results, int nextScanPage, bool hasMore})> fetchPupilOnlyArticles({
    String query = '',
    int page = 1,
    int pageSize = 30,
  }) async {
    final cleanQuery = query.trim();
    final selectedLangs = getSelectedLanguages();
    String targetLang = selectedLangs.length == 1 ? selectedLangs.first : 'all';

    final accumulatedPupilOnly = <QueryResult>[];
    var currentPage = page;
    var consecutiveEmptyBatches = 0;
    bool hasMore = true;

    // E-Hentai 최신 피드는 1회만 조회하여 루프 간 공유
    final ehIds = <int>{};
    final ehTitles = <String>{};
    bool ehFetched = false;

    while (accumulatedPupilOnly.length < 15 && consecutiveEmptyBatches < 6) {
      final ids = await fetchGalleryIdsForQuery(
        query: cleanQuery,
        page: currentPage,
        pageSize: pageSize,
        targetLang: targetLang,
      );

      // Hitomi Nozomi 범위 바이트가 완전히 끝난 경우 (진짜 인덱스 종료)
      if (ids.isEmpty) {
        hasMore = false;
        break;
      }

      // Hitomi 메타데이터 병렬 로딩
      final hitomiList = <QueryResult>[];
      const chunkSize = 25;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
        final chunk = ids.sublist(i, end);
        final chunkFutures = chunk.map((id) => _idQueryHitomiFast(id));
        hitomiList.addAll(await Future.wait(chunkFutures));
      }

      if (hitomiList.isEmpty) {
        currentPage++;
        consecutiveEmptyBatches++;
        continue;
      }

      // 1) 세션 캐시 확인: 이미 분류된 작품은 네트워크/DB 대조 없이 즉시 처리
      final uncachedHitomiList = <QueryResult>[];
      final candidates = <QueryResult>[];

      for (final hQr in hitomiList) {
        final cached = _sessionBadgeCache[hQr.id()];
        if (cached != null) {
          if (cached == 'pupil_only') {
            hQr.result['is_pupil_only'] = true;
            hQr.result['source'] = 'pupil_only';
            candidates.add(hQr);
          }
          continue;
        }
        uncachedHitomiList.add(hQr);
      }

      // 2) 캐시되지 않은 신규 ID만 DB 및 E-Hentai 대조군 마련
      if (uncachedHitomiList.isNotEmpty) {
        if (!ehFetched) {
          ehFetched = true;
          try {
            final ehQuery = formatEHentaiQuery(cleanQuery, targetLang);
            final ehList = await HentaiManager.searchEHentai(ehQuery, 0)
                .timeout(const Duration(seconds: 3), onTimeout: () => <QueryResult>[]);
            for (final item in ehList) {
              ehIds.add(item.id());
              if ((item.title() ?? '').isNotEmpty) {
                ehTitles.add(item.title()!);
              }
            }
          } catch (_) {}
        }

        await verifyAndTagPupilArticles(
          uncachedHitomiList,
          knownEhIds: ehIds,
          knownEhTitles: ehTitles,
        );

        for (final hQr in uncachedHitomiList) {
          if (hQr.result['is_pupil_only'] == true) {
            candidates.add(hQr);
          }
        }
      }

      if (candidates.isNotEmpty) {
        accumulatedPupilOnly.addAll(candidates);
      } else {
        consecutiveEmptyBatches++;
      }
      currentPage++;
    }

    accumulatedPupilOnly.sort((a, b) => b.id().compareTo(a.id()));
    return (
      results: accumulatedPupilOnly,
      nextScanPage: currentPage,
      hasMore: hasMore,
    );
  }

  static bool _articleCacheTableInitialized = false;

  static Future<void> _ensureArticleCacheTable(DataBaseManager db) async {
    if (_articleCacheTableInitialized) return;
    try {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS ArticleCache (Id INTEGER PRIMARY KEY, Data TEXT)',
      );
      _articleCacheTableInitialized = true;
    } catch (_) {}
  }

  static QueryResult? getCachedMetadata(int id) {
    final cached = _sessionMetadataCache[id];
    if (cached != null) {
      return QueryResult(result: Map<String, dynamic>.from(cached.result));
    }
    return null;
  }

  static void cacheMetadata(QueryResult qr) {
    final id = qr.id();
    _sessionMetadataCache[id] = qr;

    // 디스크(user.db) 영구 캐시 비동기 저장
    Future.microtask(() async {
      try {
        final db = await CommonUserDatabase.getInstance();
        await _ensureArticleCacheTable(db);
        final jsonStr = jsonEncode(qr.result);
        await db.insertOrReplace('ArticleCache', {
          'Id': id,
          'Data': jsonStr,
        });
      } catch (e) {
        Logger.warning('[HybridLoader.cacheMetadata] disk cache error: $e');
      }
    });
  }

  /// ids 목록 중 이미 ArticleCache(로컬 디스크)에 저장된 메타데이터를 일괄 조회
  static Future<Map<int, QueryResult>> getCachedMetadataBatch(
    List<int> ids,
  ) async {
    final result = <int, QueryResult>{};
    if (ids.isEmpty) return result;

    // 1. 메모리 캐시 먼저 확인
    final missingIds = <int>[];
    for (final id in ids) {
      final mem = _sessionMetadataCache[id];
      if (mem != null) {
        result[id] = QueryResult(result: Map<String, dynamic>.from(mem.result));
      } else {
        missingIds.add(id);
      }
    }

    if (missingIds.isEmpty) return result;

    // 2. 디스크 캐시(user.db)에서 일괄 쿼리
    try {
      final db = await CommonUserDatabase.getInstance();
      await _ensureArticleCacheTable(db);

      const int chunkSize = 500;
      for (var i = 0; i < missingIds.length; i += chunkSize) {
        final chunk = missingIds.sublist(
          i,
          i + chunkSize > missingIds.length ? missingIds.length : i + chunkSize,
        );
        final rows = await db.query(
          'SELECT Id, Data FROM ArticleCache WHERE Id IN (${chunk.join(',')})',
        );
        for (final row in rows) {
          try {
            final id = row['Id'] as int;
            final dataStr = row['Data'] as String;
            final map = jsonDecode(dataStr) as Map<String, dynamic>;
            final qr = QueryResult(result: map);
            _sessionMetadataCache[id] = qr;
            result[id] = qr;
          } catch (_) {}
        }
      }
    } catch (e) {
      Logger.warning('[HybridLoader.getCachedMetadataBatch] error: $e');
    }

    return result;
  }

  /// 외부 호출용 초고속 Hitomi 경량 로더 (galleryblock HTML 1회 호출)
  static Future<QueryResult> idQueryHitomiFast(int id) async =>
      _idQueryHitomiFast(id);

  /// galleryinfo.js 2차 요청 없이 galleryblock HTML 1회 요청만으로
  /// 검색 목록에 필요한 핵심 메타데이터를 초고속 수집하는 경량 로더
  static Future<QueryResult> _idQueryHitomiFast(int id) async {
    final cached = _sessionMetadataCache[id];
    if (cached != null) {
      return QueryResult(result: Map<String, dynamic>.from(cached.result));
    }

    try {
      final headers =
          await ScriptManager.runHitomiGetHeaderContent(id.toString());
      final res = await http.get(
        'https://ltn.gold-usergeneratedcontent.net/galleryblock/$id.html',
        headers: headers,
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
      final article = await HitomiParser.parseGalleryBlock(res.body);

      String encodePipeValues(List<String>? list) {
        if (list == null || list.isEmpty) return 'N/A';
        return '|${list.join('|')}|';
      }

      final meta = {
        'Id': id,
        'Title': article['Title'] ?? '#$id',
        'Artists': encodePipeValues(
          article['Artists'] is List<String>
              ? article['Artists'] as List<String>
              : null,
        ),
        'Groups': null,
        'Characters': null,
        'Series': encodePipeValues(
          article['Series'] is List<String>
              ? article['Series'] as List<String>
              : null,
        ),
        'Tags': encodePipeValues(
          article['Tags'] is List<String>
              ? article['Tags'] as List<String>
              : null,
        ),
        'Files': null,
        'Type': article['Type'] ?? 'N/A',
        'Language': article['Language'] ?? 'N/A',
        'Published': article['Published'],
        'Thumbnail': article['Thumbnail'],
        'ExistOnHitomi': 1,
        'source': 'pupil',
      };
      final qr = QueryResult(result: meta);
      _sessionMetadataCache[id] = qr;
      cacheMetadata(qr);
      return qr;
    } catch (e) {
      return QueryResult(
        result: {'Id': id, 'Title': '#$id', 'ExistOnHitomi': 1, 'source': 'pupil'},
      );
    }
  }

  /// 메인 화면용 하이브리드 작품 로더 (기본 검색 시 호출)
  /// Violet(E-Hentai) 방식과 Pupil(Hitomi Nozomi) 방식으로 불러온 모든 작품을
  /// 병렬로 수집하여 중복 제거 후 합쳐서 반환합니다.
  /// 둘 다 존재하는 작품은 'common', Hitomi만 있는 작품은 'pupil', E-Hentai만 있는 작품은 'violet' 소스 뱃지가 부여됩니다.
  static Future<List<QueryResult>> fetchMainHybridArticles({
    String query = '',
    int page = 1,
    int pageSize = 50,
    SearchSortMode sortMode = SearchSortMode.latest,
  }) async {
    final cleanQuery = query.trim();

    // 순수 숫자(품번) 또는 id:숫자 단독 검색인 경우 직결 처리 (초고속 1건 반환)
    final numericId = int.tryParse(cleanQuery) ??
        (cleanQuery.toLowerCase().startsWith('id:')
            ? int.tryParse(cleanQuery.substring(3).trim())
            : null);
    if (numericId != null) {
      if (page > 1) return [];
      try {
        final hitomiQr = await _idQueryHitomiFast(numericId);
        try {
          final db = await DataBaseManager.getInstance();
          if (db.db != null && db.db!.isOpen) {
            final dbMatches = await db.query(
              'SELECT * FROM HitomiColumnModel WHERE Id = $numericId',
            );
            if (dbMatches.isNotEmpty) {
              final row = dbMatches.first;
              hitomiQr.result.addAll(row);
              hitomiQr.result['source'] = 'common';
              hitomiQr.result['is_common'] = true;
            }
          }
        } catch (_) {}
        return [hitomiQr];
      } catch (e, st) {
        Logger.error('[HybridLoader-NumericIdQuery] E: $e\n$st');
        return [];
      }
    }

    final selectedLangs = getSelectedLanguages();
    String targetLang = selectedLangs.length == 1 ? selectedLangs.first : 'all';

    // 1) 정렬 조건(order:) 추출
    SearchSortMode effectiveSortMode = sortMode;
    final orderMatch = RegExp(r'(?:^|[\s\(])order:([a-zA-Z0-9_-]+)', caseSensitive: false).firstMatch(cleanQuery);
    if (orderMatch != null) {
      final o = orderMatch.group(1)!.toLowerCase();
      if (o == 'week' || o == 'popular-week') {
        effectiveSortMode = SearchSortMode.popularWeek;
      } else if (o == 'month' || o == 'popular-month') {
        effectiveSortMode = SearchSortMode.popularMonth;
      } else if (o == 'year' || o == 'popular-year') {
        effectiveSortMode = SearchSortMode.popularYear;
      } else if (o == 'today' || o == 'popular-today') {
        effectiveSortMode = SearchSortMode.popularToday;
      } else if (o == 'popular' || o == 'all' || o == 'popular-all') {
        effectiveSortMode = SearchSortMode.popularAll;
      } else if (o == 'latest') {
        effectiveSortMode = SearchSortMode.latest;
      }
    }

    // 2) 언어 토큰 분석 및 정규화
    bool isLanguageToken(String rawToken) {
      final t = rawToken.replaceAll(RegExp(r'[\(\)]'), '').trim().toLowerCase();
      if (t.isEmpty) return true;
      if (t.startsWith('lang:') || t.startsWith('language:')) {
        final langVal = t.split(':').last.trim();
        if (langVal == 'ko' || langVal == 'korea' || langVal == 'korean' || langVal == '한국어') {
          targetLang = 'korean';
        } else if (langVal == 'ja' || langVal == 'japan' || langVal == 'japanese' || langVal == '일본어') {
          targetLang = 'japanese';
        } else if (langVal == 'en' || langVal == 'english' || langVal == '영어') {
          targetLang = 'english';
        } else if (langVal == 'zh' || langVal == 'chinese' || langVal == '중국어') {
          targetLang = 'chinese';
        } else {
          targetLang = langVal;
        }
        return true;
      }
      if (t == 'korean' || t == 'ko' || t == 'korea' || t == '한국어') {
        targetLang = 'korean';
        return true;
      }
      if (t == 'japanese' || t == 'ja' || t == 'japan' || t == '일본어') {
        targetLang = 'japanese';
        return true;
      }
      if (t == 'english' || t == 'en' || t == '영어') {
        targetLang = 'english';
        return true;
      }
      if (t == 'chinese' || t == 'zh' || t == '중국어') {
        targetLang = 'chinese';
        return true;
      }
      if (t == 'tag:korean' || t == 'tag:japanese' || t == 'tag:english' || t == 'tag:chinese') {
        return true;
      }
      return false;
    }

    // 3) random 검색 및 seed 분리
    bool isRandom = false;
    double? randomSeed;
    final queryTokens = cleanQuery.split(' ');
    if (queryTokens.any((x) => x == 'random' || x.startsWith('random:'))) {
      isRandom = true;
      for (final t in queryTokens) {
        if (t.startsWith('random:')) {
          randomSeed = double.tryParse(t.split('random:').last);
          break;
        }
      }
      randomSeed ??= (DateTime.now().microsecondsSinceEpoch % 10000) / 1000.0 + 1.0;
    }

    // 온라인 및 태그 검색용 순수 검색어 (random, order 제외)
    final pureTokens = queryTokens.where(
      (x) => x != 'random' && !x.startsWith('random:') && !x.startsWith('order:'),
    ).toList();

    // 언어 토큰까지 검사하여 targetLang을 추출하고 비언어 토큰만 분리
    final nonLangTokens = pureTokens.where((x) => !isLanguageToken(x)).toList();
    final pureQueryWithoutLang = nonLangTokens
        .map((x) => x.replaceAll(RegExp(r'[\(\)]'), '').trim())
        .where((x) => x.isNotEmpty)
        .join(' ')
        .trim();

    final pureQuery = pureTokens.join(' ').trim();

    // 2) 번호(Id) 및 날짜(Date) 범위 필터 추출
    int? filterMinId;
    int? filterMaxId;
    final idRangeMatch = RegExp(r'id:(\d+)(?:~|\.\.|\-)(\d+)', caseSensitive: false).firstMatch(cleanQuery);
    if (idRangeMatch != null) {
      filterMinId = int.tryParse(idRangeMatch.group(1)!);
      filterMaxId = int.tryParse(idRangeMatch.group(2)!);
    }
    final idGteMatch = RegExp(r'id(?:>=|>)(\d+)', caseSensitive: false).firstMatch(cleanQuery);
    if (idGteMatch != null) filterMinId = int.tryParse(idGteMatch.group(1)!);
    final idLteMatch = RegExp(r'id(?:<=|<)(\d+)', caseSensitive: false).firstMatch(cleanQuery);
    if (idLteMatch != null) filterMaxId = int.tryParse(idLteMatch.group(1)!);

    DateTime? filterMinDate;
    DateTime? filterMaxDate;
    final dateRangeMatch = RegExp(r'(?:date|published):(\d{4}(?:-\d{2}-\d{2})?)(?:~|\.\.)(\d{4}(?:-\d{2}-\d{2})?)', caseSensitive: false).firstMatch(cleanQuery);
    if (dateRangeMatch != null) {
      var sStr = dateRangeMatch.group(1)!;
      var eStr = dateRangeMatch.group(2)!;
      if (sStr.length == 4) sStr = '$sStr-01-01';
      if (eStr.length == 4) eStr = '$eStr-12-31';
      filterMinDate = DateTime.tryParse(sStr);
      filterMaxDate = DateTime.tryParse('$eStr 23:59:59');
    }
    final dateGteMatch = RegExp(r'(?:date|published)(?:>=|>)(\d{4}(?:-\d{2}-\d{2})?)', caseSensitive: false).firstMatch(cleanQuery);
    if (dateGteMatch != null) {
      var sStr = dateGteMatch.group(1)!;
      if (sStr.length == 4) sStr = '$sStr-01-01';
      filterMinDate = DateTime.tryParse(sStr);
    }
    final dateLteMatch = RegExp(r'(?:date|published)(?:<=|<)(\d{4}(?:-\d{2}-\d{2})?)', caseSensitive: false).firstMatch(cleanQuery);
    if (dateLteMatch != null) {
      var eStr = dateLteMatch.group(1)!;
      if (eStr.length == 4) eStr = '$eStr-12-31';
      filterMaxDate = DateTime.tryParse('$eStr 23:59:59');
    }

    // 1) Pupil 방식: fetchGalleryIdsForQuery 사용 (random 태그 제외한 pureQuery 사용)
    final pupilFuture = Future<List<QueryResult>>(() async {
      try {
        List<int> ids = [];
        if (effectiveSortMode != SearchSortMode.latest && pureQueryWithoutLang.isEmpty) {
          final popularUrl = HitomiNozomi.getPopularIndexUrl(effectiveSortMode, targetLang);
          ids = await HitomiNozomi.fetchGalleryIds(popularUrl, page, pageSize: pageSize);
        } else if (isRandom) {
          ids = await fetchRandomGalleryIdsForQuery(
            query: pureQuery,
            targetLang: targetLang,
            selectedLangs: selectedLangs,
            count: pageSize,
            seed: randomSeed,
            page: page,
          );
        } else if (pureQuery.isEmpty && selectedLangs.length > 1) {
          // 복수 언어가 설정된 경우 각 언어 인덱스를 분할/병렬 로드하여 합침
          final subPageSize = (pageSize / selectedLangs.length).ceil() + 5;
          final subIds = await Future.wait(
            selectedLangs.map((lang) => HitomiNozomi.fetchGalleryIds(
              HitomiNozomi.getLanguageIndexUrl(lang),
              page,
              pageSize: subPageSize,
            )),
          );
          final mergedSet = <int>{};
          for (final list in subIds) {
            mergedSet.addAll(list);
          }
          ids = mergedSet.toList();
        } else {
          ids = await fetchGalleryIdsForQuery(
            query: pureQuery,
            page: page,
            pageSize: pageSize,
            targetLang: targetLang,
          );
        }
        if (ids.isEmpty) return [];

        final hitomiList = <QueryResult>[];
        const chunkSize = 25;
        for (var i = 0; i < ids.length; i += chunkSize) {
          final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
          final chunk = ids.sublist(i, end);
          final chunkFutures = chunk.map((id) => _idQueryHitomiFast(id));
          hitomiList.addAll(await Future.wait(chunkFutures));
        }
        for (final qr in hitomiList) {
          qr.result['source'] = 'pupil';
        }
        return hitomiList;
      } catch (e, st) {
        Logger.error('[HybridLoader-Main-Hitomi] E: $e\n$st');
        return [];
      }
    }).timeout(
      const Duration(seconds: 12),
      onTimeout: () => <QueryResult>[],
    );

    // 2) Violet 웹 방식: E-Hentai 검색 (random 태그 제외한 pureQuery 사용)
    final violetFuture = Future<List<QueryResult>>(() async {
      if (effectiveSortMode != SearchSortMode.latest && pureQueryWithoutLang.isEmpty) return [];
      try {
        final ehQuery = formatEHentaiQuery(pureQuery, targetLang);
        if (pageSize <= 25) {
          final offset = (page - 1) * pageSize;
          final list = await HentaiManager.searchEHentai(ehQuery, offset);
          for (final qr in list) {
            qr.result['source'] = 'violet';
          }
          return list;
        } else {
          final pagesToFetch = (pageSize / 25).ceil();
          final baseOffset = (page - 1) * pageSize;
          final futures = List.generate(
            pagesToFetch,
            (i) => HentaiManager.searchEHentai(ehQuery, baseOffset + i * 25),
          );
          final pagesResults = await Future.wait(futures);
          final mergedList = <QueryResult>[];
          for (final list in pagesResults) {
            for (final qr in list) {
              qr.result['source'] = 'violet';
            }
            mergedList.addAll(list);
          }
          return mergedList;
        }
      } catch (e, st) {
        Logger.error('[HybridLoader-Main-Violet] E: $e\n$st');
        return [];
      }
    }).timeout(
      const Duration(seconds: 10),
      onTimeout: () => <QueryResult>[],
    );

    // 3) 로컬 DB 방식: HitomiColumnModel 검색 (Triple Hybrid, random 지원)
    final localDbFuture = Future<List<QueryResult>>(() async {
      if (effectiveSortMode != SearchSortMode.latest && pureQueryWithoutLang.isEmpty) return [];
      try {
        final db = await DataBaseManager.getInstance();
        if (db.db == null || !db.db!.isOpen) return [];

        String sqlQuery;
        final offset = (page - 1) * pageSize;
        final orderBy = isRandom
            ? 'ORDER BY Id * $randomSeed - ROUND(Id * $randomSeed - 0.5, 0) DESC'
            : 'ORDER BY Id DESC';

        if (pureQuery.isEmpty) {
          if (targetLang != 'all') {
            sqlQuery = 'SELECT * FROM HitomiColumnModel WHERE Language=\'$targetLang\' $orderBy LIMIT $pageSize OFFSET $offset';
          } else {
            sqlQuery = 'SELECT * FROM HitomiColumnModel $orderBy LIMIT $pageSize OFFSET $offset';
          }
        } else {
          final translated = translate2query(pureQuery);
          sqlQuery = '$translated $orderBy LIMIT $pageSize OFFSET $offset';
        }

        final rows = await db.query(sqlQuery);
        return rows.map((r) {
          final map = Map<String, dynamic>.from(r);
          map['source'] = 'common';
          map['is_common'] = true;
          return QueryResult(result: map);
        }).toList();
      } catch (_) {
        return [];
      }
    }).timeout(
      const Duration(seconds: 3),
      onTimeout: () => <QueryResult>[],
    );

    final responses = await Future.wait([pupilFuture, violetFuture, localDbFuture])
        .timeout(
          const Duration(seconds: 14),
          onTimeout: () => [<QueryResult>[], <QueryResult>[], <QueryResult>[]],
        );
    final pupilList = responses[0];
    final violetList = responses[1];
    final localDbList = responses[2];

    final merged = <QueryResult>[];
    final seenIds = <int>{};
    final seenTitles = <String>{};

    // 로컬 DB 검색 결과 우선 반영 (Violet 공식 DB에 존재하는 100% 공통 작품)
    for (final lItem in localDbList) {
      final lId = lItem.id();
      final lTitle = lItem.title() ?? '';
      seenIds.add(lId);
      if (lTitle.isNotEmpty) seenTitles.add(normalizeTitle(lTitle));
      _sessionBadgeCache[lId] = 'common';
      merged.add(lItem);
    }

    // Pupil 최신 결과 반영
    for (final item in pupilList) {
      final id = item.id();
      final title = item.title() ?? '';

      // 이미 로컬 DB에 등록된 작품인 경우 승격
      if (seenIds.contains(id)) {
        final existing = merged.where((m) => m.id() == id).firstOrNull;
        if (existing != null) {
          existing.result['source'] = 'common';
          existing.result['is_common'] = true;
          _sessionBadgeCache[id] = 'common';
        }
        continue;
      }

      final existingByTitle = merged.where((m) =>
          isLanguageMatched(m, item) &&
          isTitleMatched(m.title() ?? '', title)).firstOrNull;
      if (existingByTitle != null) {
        existingByTitle.result['source'] = 'common';
        existingByTitle.result['is_common'] = true;
        _sessionBadgeCache[existingByTitle.id()] = 'common';
        continue;
      }

      seenIds.add(id);
      if (title.isNotEmpty) seenTitles.add(normalizeTitle(title));
      merged.add(item);
    }

    // E-Hentai 결과 추가 병합 및 공통 작품 승격
    final ehIds = <int>{};
    final ehTitles = <String>{};
    for (final vItem in violetList) {
      final vId = vItem.id();
      final vTitle = vItem.title() ?? '';
      ehIds.add(vId);
      if (vTitle.isNotEmpty) ehTitles.add(vTitle);

      final existing = merged.where((m) {
        if (m.id() == vId) return true;
        return isLanguageMatched(m, vItem) && isTitleMatched(m.title() ?? '', vTitle);
      }).firstOrNull;

      if (existing != null) {
        existing.result['source'] = 'common';
        existing.result['is_common'] = true;
        if (vItem.ehash() != null) existing.result['EHash'] = vItem.ehash();
        _sessionBadgeCache[existing.id()] = 'common';
      } else {
        if (!seenIds.contains(vId)) {
          seenIds.add(vId);
          vItem.result['source'] = 'violet';
          _sessionBadgeCache[vId] = 'violet';
          merged.add(vItem);
        }
      }
    }

    // 로컬 DB, 북마크 DB, E-Hentai 대조군을 통해 pupil 작품 전수 정밀 검증
    final pupilItems = merged.where((m) => m.result['source'] == 'pupil').toList();
    if (pupilItems.isNotEmpty) {
      await verifyAndTagPupilArticles(
        pupilItems,
        knownEhIds: ehIds,
        knownEhTitles: ehTitles,
      );
    }

    // 번호(Id) 및 날짜(Date) 범위 필터 적용
    if (filterMinId != null || filterMaxId != null || filterMinDate != null || filterMaxDate != null) {
      merged.retainWhere((item) {
        final id = item.id();
        if (filterMinId != null && id < filterMinId) return false;
        if (filterMaxId != null && id > filterMaxId) return false;
        if (filterMinDate != null || filterMaxDate != null) {
          final dt = item.getDateTime();
          if (dt != null) {
            if (filterMinDate != null && dt.isBefore(filterMinDate)) return false;
            if (filterMaxDate != null && dt.isAfter(filterMaxDate)) return false;
          }
        }
        return true;
      });
    }

    if (isRandom && randomSeed != null) {
      final seed = randomSeed;
      // random 검색일 때는 일관된 seed 정렬 유지
      merged.sort((a, b) {
        final scoreA = (a.id() * seed) - (a.id() * seed).floor();
        final scoreB = (b.id() * seed) - (b.id() * seed).floor();
        return scoreB.compareTo(scoreA);
      });
    } else if (effectiveSortMode != SearchSortMode.latest && pureQueryWithoutLang.isEmpty) {
      // Hitomi 공식 CDN 인기순 인덱스(1위~50위) 순서를 100% 보존
    } else if (effectiveSortMode != SearchSortMode.latest) {
      // 태그 검색어 등과 함께 사용된 인기순은 Population 인기도 랭킹으로 정렬
      await Population.ensureLoaded();
      Population.sortByPopulation(merged);
    } else {
      merged.sort((a, b) => b.id().compareTo(a.id()));
    }

    return merged;
  }

  /// 해당 작품이 Violet에 없는 순수 Pupil 독점작인지 여부를 판별합니다.
  static bool isPupilOnly(QueryResult item) {
    final res = item.result;
    if (res['is_common'] == true || res['source'] == 'common' || res['source'] == 'violet') {
      return false;
    }
    if (res['EHash'] != null) return false;
    final cached = _sessionBadgeCache[item.id()];
    if (cached == 'common' || cached == 'violet') return false;
    if (cached == 'pupil_only' || res['is_pupil_only'] == true || res['source'] == 'pupil_only') {
      return true;
    }
    // 명시적으로 검증되지 않은 작품은 Pupil 단독작으로 노출하지 않음 (안전 가드)
    return false;
  }
}
