// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:async';
import 'package:violet/component/hentai.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/component/hitomi/hitomi_parser.dart';
import 'package:violet/database/database.dart';
import 'package:violet/database/query.dart';
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
  }) async {
    final results = <QueryResult>[];
    final seenIds = <int>{};
    final seenTitles = <String>{};

    final selectedLangs = getSelectedLanguages();
    String targetLang = selectedLangs.length == 1 ? selectedLangs.first : 'all';

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

    // 1) Hitomi Nozomi Range Request (Pupil 방식)
    final hitomiFuture = Future<List<QueryResult>>(() async {
      try {
        List<int> ids = [];
        if (targetLang != 'all') {
          ids = await HitomiNozomi.fetchGalleryIds(
            getNozomiUrl(targetLang),
            page,
            pageSize: 30,
          );
        }
        if (ids.isEmpty) {
          ids = await HitomiNozomi.fetchGalleryIds(
            getNozomiUrl('all'),
            page,
            pageSize: 30,
          );
        }
        if (ids.isEmpty) return [];

        // DB 조회 없이 순수 웹(Hitomi)에서 메타데이터 로딩
        final fetchedList = <QueryResult>[];
        const chunkSize = 8;
        for (var i = 0; i < ids.length; i += chunkSize) {
          final end = (i + chunkSize < ids.length) ? i + chunkSize : ids.length;
          final chunk = ids.sublist(i, end);
          final chunkFutures = chunk.map((id) async {
            try {
              final qr = await HentaiManager.idQueryHitomi(id.toString());
              qr.result['ExistOnHitomi'] = 1;
              qr.result['source'] = 'pupil';
              return qr;
            } catch (e) {
              return QueryResult(result: {
                'Id': id,
                'Title': '$name #$id',
                'Artists': name,
                'ExistOnHitomi': 1,
                'source': 'pupil',
              });
            }
          });
          fetchedList.addAll(await Future.wait(chunkFutures));
        }

        return fetchedList;
      } catch (e, st) {
        Logger.error('[HybridLoader-Hitomi] E: $e\n$st');
        return [];
      }
    }).timeout(
      const Duration(seconds: 4),
      onTimeout: () => <QueryResult>[],
    );

    // 2) E-Hentai 검색 (Violet 웹 검색 방식)
    final ehentaiFuture = Future<List<QueryResult>>(() async {
      try {
        final langPrefix = targetLang != 'all' ? 'language:$targetLang ' : '';
        final queryTag = '$langPrefix$type:"$name"';
        final ehList = await HentaiManager.searchEHentai(queryTag, 0);
        return ehList;
      } catch (e, st) {
        Logger.error('[HybridLoader-EHentai] E: $e\n$st');
        return [];
      }
    }).timeout(
      const Duration(seconds: 4),
      onTimeout: () => <QueryResult>[],
    );

    // 두 소스를 병렬로 동시 대기 (Zero Latency)
    final responses = await Future.wait([hitomiFuture, ehentaiFuture])
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => [<QueryResult>[], <QueryResult>[]],
        );
    final hitomiResults = responses[0];
    final ehResults = responses[1];

    void addResult(QueryResult qr) {
      final id = qr.id();
      final title = (qr.title() ?? '').trim().toLowerCase();

      // 언어 필터링 (한국어 등 지정 언어가 설정된 경우)
      if (targetLang != 'all') {
        final qrLang = (qr.language() ?? '').toString().toLowerCase();
        final tags = (qr.tags() ?? '').toString().toLowerCase();
        final qrTitle = (qr.title() ?? '').toString().toLowerCase();

        final matchLang = qrLang.contains(targetLang) ||
            tags.contains(targetLang) ||
            (targetLang == 'korean' &&
                (qrLang == 'korean' ||
                    tags.contains('korean') ||
                    qrTitle.contains('[한국어]') ||
                    qrTitle.contains('(한국어)')));

        if (!matchLang && qrLang.isNotEmpty && qrLang != targetLang) {
          return;
        }
      }

      if (seenIds.contains(id)) return;
      if (title.isNotEmpty && seenTitles.contains(title)) return;

      seenIds.add(id);
      if (title.isNotEmpty) seenTitles.add(title);
      results.add(qr);
    }

    // Hitomi 최신 결과 우선 반영
    for (final item in hitomiResults) {
      addResult(item);
    }

    // E-Hentai 결과 추가 병합 및 공통 작품 승격
    for (final item in ehResults) {
      final itemTitle = normalizeTitle(item.title() ?? '');
      final existing = results.where((r) {
        if (r.id() == item.id()) return true;
        final rTitle = normalizeTitle(r.title() ?? '');
        return rTitle.isNotEmpty &&
            (rTitle == itemTitle ||
                (rTitle.length >= 5 && itemTitle.contains(rTitle)) ||
                (itemTitle.length >= 5 && rTitle.contains(itemTitle)));
      }).firstOrNull;

      if (existing != null) {
        existing.result['source'] = 'common';
        existing.result['is_common'] = true;
        if (item.ehash() != null) existing.result['EHash'] = item.ehash();
      } else {
        item.result['source'] = 'violet';
        addResult(item);
      }
    }

    // ID 기준 최신순 정렬
    results.sort((a, b) => b.id().compareTo(a.id()));

    return results;
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

  /// 사용자가 입력한 다양한 검색어(태그, 작가, 그룹, 시리즈, 캐릭터, 업로더 또는 성별 없는 태그)를
  /// Hitomi Nozomi 인덱스 URL로 스마트하게 변환하여 Gallery ID 목록을 Range Header로 로딩합니다.
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
          // 'common'이나 'violet'은 이미 E-Hentai에 있는 것이 확인되었으므로 제외
          continue;
        }
        uncachedHitomiList.add(hQr);
      }

      // 2) 캐시되지 않은 신규 ID만 DB 및 E-Hentai 대조군 마련
      if (uncachedHitomiList.isNotEmpty) {
        // 로컬 DB 전수 대조 (0ms)
        try {
          final db = await DataBaseManager.getInstance();
          if (db.db != null && db.db!.isOpen) {
            final idListStr = uncachedHitomiList.map((e) => e.id()).join(',');
            if (idListStr.isNotEmpty) {
              final dbMatches = await db.query(
                'SELECT Id, Title, EHash FROM HitomiColumnModel WHERE Id IN ($idListStr)',
              );
              for (final row in dbMatches) {
                final rid = row['Id'] as int?;
                if (rid != null) ehIds.add(rid);
                final t = normalizeTitle(row['Title'] as String? ?? '');
                if (t.isNotEmpty) ehTitles.add(t);
              }
            }
          }
        } catch (_) {}

        // E-Hentai 최신 피드는 1회만 로딩하여 캐싱 재활용 (지연 0초)
        if (!ehFetched) {
          ehFetched = true;
          try {
            final ehQuery = formatEHentaiQuery(cleanQuery, targetLang);
            final ehList = await HentaiManager.searchEHentai(ehQuery, 0)
                .timeout(const Duration(seconds: 3), onTimeout: () => <QueryResult>[]);
            for (final item in ehList) {
              ehIds.add(item.id());
              final t = normalizeTitle(item.title() ?? '');
              if (t.isNotEmpty) ehTitles.add(t);
            }
          } catch (_) {}
        }

        for (final hQr in uncachedHitomiList) {
          final hId = hQr.id();
          if (ehIds.contains(hId)) {
            _sessionBadgeCache[hId] = 'common';
            continue;
          }

          final hTitle = normalizeTitle(hQr.title() ?? '');
          bool existsOnEh = false;
          if (hTitle.isNotEmpty && ehTitles.isNotEmpty) {
            for (final ehTitle in ehTitles) {
              if (hTitle == ehTitle ||
                  (hTitle.length >= 6 && ehTitle.contains(hTitle)) ||
                  (ehTitle.length >= 6 && hTitle.contains(ehTitle))) {
                existsOnEh = true;
                break;
              }
            }
          }
          if (existsOnEh) {
            _sessionBadgeCache[hId] = 'common';
            continue;
          }

          hQr.result['is_pupil_only'] = true;
          hQr.result['source'] = 'pupil_only';
          _sessionBadgeCache[hId] = 'pupil_only';
          candidates.add(hQr);
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
      ).timeout(const Duration(seconds: 3));

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
    int pageSize = 25,
  }) async {
    final cleanQuery = query.trim();
    final selectedLangs = getSelectedLanguages();
    String targetLang = selectedLangs.length == 1 ? selectedLangs.first : 'all';

    // 1) Pupil 방식: fetchGalleryIdsForQuery 사용
    final pupilFuture = Future<List<QueryResult>>(() async {
      try {
        List<int> ids = [];
        if (cleanQuery.isEmpty && selectedLangs.length > 1) {
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
            query: cleanQuery,
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
      const Duration(seconds: 8),
      onTimeout: () => <QueryResult>[],
    );

    // 2) Violet 웹 방식: E-Hentai 검색
    final violetFuture = Future<List<QueryResult>>(() async {
      try {
        final ehQuery = formatEHentaiQuery(cleanQuery, targetLang);
        final offset = (page - 1) * pageSize;
        final list = await HentaiManager.searchEHentai(ehQuery, offset);
        for (final qr in list) {
          qr.result['source'] = 'violet';
        }
        return list;
      } catch (e, st) {
        Logger.error('[HybridLoader-Main-Violet] E: $e\n$st');
        return [];
      }
    }).timeout(
      const Duration(seconds: 8),
      onTimeout: () => <QueryResult>[],
    );

    final responses = await Future.wait([pupilFuture, violetFuture])
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () => [<QueryResult>[], <QueryResult>[]],
        );
    final pupilList = responses[0];
    final violetList = responses[1];

    final merged = <QueryResult>[];
    final seenIds = <int>{};
    final seenTitles = <String>{};

    for (final item in pupilList) {
      final id = item.id();
      final title = normalizeTitle(item.title() ?? '');
      seenIds.add(id);
      if (title.isNotEmpty) seenTitles.add(title);
      merged.add(item);
    }

    for (final vItem in violetList) {
      final vId = vItem.id();
      final vTitle = normalizeTitle(vItem.title() ?? '');

      final existing = merged.where((m) {
        if (m.id() == vId) return true;
        final mTitle = normalizeTitle(m.title() ?? '');
        return mTitle.isNotEmpty &&
            (mTitle == vTitle ||
                (mTitle.length >= 5 && vTitle.contains(mTitle)) ||
                (vTitle.length >= 5 && mTitle.contains(vTitle)));
      }).firstOrNull;

      if (existing != null) {
        // 둘 다 있는 경우: Violet & Pupil 공통으로 승격
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

    for (final item in merged) {
      if (item.result['source'] == 'pupil') {
        item.result['source'] = 'pupil_only';
        item.result['is_pupil_only'] = true;
        _sessionBadgeCache[item.id()] = 'pupil_only';
      }
    }

    merged.sort((a, b) => b.id().compareTo(a.id()));

    return merged;
  }

  /// 해당 작품이 Violet에 없는 순수 Pupil 독점작인지 여부를 판별합니다.
  static bool isPupilOnly(QueryResult item) {
    final res = item.result;
    if (res['is_pupil_only'] == true || res['source'] == 'pupil_only') return true;
    final cached = _sessionBadgeCache[item.id()];
    if (cached == 'pupil_only') return true;
    if (cached == 'common' || cached == 'violet') return false;
    return res['source'] == 'pupil' && res['is_common'] != true && res['EHash'] == null;
  }
}
