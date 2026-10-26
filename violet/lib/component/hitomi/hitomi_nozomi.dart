// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:typed_data';
import 'package:violet/network/wrapper.dart' as http;
import 'package:violet/log/log.dart';

/// Pupil 애플리케이션의 핵심 로딩 메커니즘을 차용한 Hitomi Nozomi Range Request Fetcher.
/// Hitomi.la의 `.nozomi` 바이너리 인덱스 파일에서 4바이트 Big-Endian 정수(갤러리 ID)를
/// HTTP Range Header (bytes=start-end)를 이용해 100바이트 단위로 실시간 비동기 로딩합니다.
class HitomiNozomi {
  static const String domain = 'ltn.gold-usergeneratedcontent.net';

  /// Nozomi URL -> 총 작품 수 인메모리 캐시
  static final Map<String, int> _totalCountCache = <String, int>{};

  /// 특정 Nozomi URL에서 지정한 페이지 범위(기본 25개 갤러리 ID)를 Range Header로 요청합니다.
  static Future<List<int>> fetchGalleryIds(
    String nozomiUrl,
    int page, {
    int pageSize = 25,
  }) async {
    try {
      final startByte = (page - 1) * pageSize * 4;
      final endByte = page * pageSize * 4 - 1;

      final response = await http.get(
        nozomiUrl,
        headers: {
          'Range': 'bytes=$startByte-$endByte',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://hitomi.la/',
        },
      );

      if (response.statusCode == 206 || response.statusCode == 200) {
        // Content-Range 헤더(예: bytes 0-15/36) 또는 Content-Length를 통해 총 작품 수 캐싱
        try {
          final contentRange = response.headers['content-range'];
          if (contentRange != null && contentRange.contains('/')) {
            final totalStr = contentRange.split('/').last.trim();
            final totalBytes = int.tryParse(totalStr);
            if (totalBytes != null && totalBytes > 0) {
              _totalCountCache[nozomiUrl] = totalBytes ~/ 4;
            }
          } else if (response.statusCode == 200) {
            _totalCountCache[nozomiUrl] = response.bodyBytes.length ~/ 4;
          }
        } catch (_) {}

        return parseNozomiBytes(Uint8List.fromList(response.bodyBytes));
      } else {
        if (response.statusCode == 404) {
          _totalCountCache[nozomiUrl] = 0;
          Logger.info(
            '[HitomiNozomi] Nozomi index not found (404): $nozomiUrl',
          );
        } else {
          Logger.warning(
            '[HitomiNozomi] Non-success range request (${response.statusCode}): $nozomiUrl',
          );
        }
      }
    } catch (e, st) {
      Logger.error('[HitomiNozomi] Exception during range request: $e\n$st');
    }
    return [];
  }

  /// 특정 Nozomi 인덱스의 총 작품 수를 반환합니다 (캐시 우선, 부재 시 Range 0-0 요청으로 전체 바이트 수 추출).
  static Future<int?> getTotalCount(String nozomiUrl) async {
    if (_totalCountCache.containsKey(nozomiUrl)) {
      return _totalCountCache[nozomiUrl];
    }
    try {
      final response = await http.get(
        nozomiUrl,
        headers: {
          'Range': 'bytes=0-0',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://hitomi.la/',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200 || response.statusCode == 206) {
        final contentRange = response.headers['content-range'];
        if (contentRange != null && contentRange.contains('/')) {
          final totalStr = contentRange.split('/').last.trim();
          final totalBytes = int.tryParse(totalStr);
          if (totalBytes != null && totalBytes >= 0) {
            final count = totalBytes ~/ 4;
            _totalCountCache[nozomiUrl] = count;
            return count;
          }
        }
        final lengthStr = response.headers['content-length'];
        if (lengthStr != null) {
          final totalBytes = int.tryParse(lengthStr);
          if (totalBytes != null && totalBytes >= 0) {
            final count = totalBytes ~/ 4;
            _totalCountCache[nozomiUrl] = count;
            return count;
          }
        }
      } else if (response.statusCode == 404) {
        _totalCountCache[nozomiUrl] = 0;
        return 0;
      }
    } catch (_) {}
    return null;
  }

  /// 4바이트 Big-Endian 정수 배열을 Dart `List<int>` ID 목록으로 바이트 언패킹(Unpack)합니다.
  static List<int> parseNozomiBytes(Uint8List bytes) {
    final ids = <int>[];
    final byteData = ByteData.sublistView(bytes);

    for (var i = 0; i + 4 <= bytes.length; i += 4) {
      final id = byteData.getUint32(i, Endian.big);
      ids.add(id);
    }
    return ids;
  }

  /// 검색어 정규화 유틸리티: 언더스코어를 공백으로 변환하고, URL용 공백을 '%20'으로 안전하게 인코딩합니다.
  static String cleanTerm(String raw) {
    var s = raw.trim();
    if (s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1).trim();
    }
    s = s.replaceAll('_', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.replaceAll(' ', '%20');
  }

  /// 메인 갤러리 전체 최신 작품 목록 URL 생성
  static String getIndexAllUrl() => 'https://$domain/index-all.nozomi';

  /// 특정 언어별 최신 작품 목록 URL 생성 (예: 'korean')
  static String getLanguageIndexUrl(String language) =>
      'https://$domain/index-$language.nozomi';

  /// 작가별 최신 작품 목록 URL 생성
  static String getArtistIndexUrl(String artist, [String language = 'all']) {
    final clean = cleanTerm(artist);
    return 'https://$domain/artist/$clean-$language.nozomi';
  }

  /// 그룹별 최신 작품 목록 URL 생성
  static String getGroupIndexUrl(String group, [String language = 'all']) {
    final clean = cleanTerm(group);
    return 'https://$domain/group/$clean-$language.nozomi';
  }

  /// 시리즈별 최신 작품 목록 URL 생성
  static String getSeriesIndexUrl(String series, [String language = 'all']) {
    final clean = cleanTerm(series);
    return 'https://$domain/series/$clean-$language.nozomi';
  }

  /// 캐릭터별 최신 작품 목록 URL 생성
  static String getCharacterIndexUrl(String character, [String language = 'all']) {
    final clean = cleanTerm(character);
    return 'https://$domain/character/$clean-$language.nozomi';
  }

  /// 업로더별 최신 작품 목록 URL 생성
  static String getUploaderIndexUrl(String uploader, [String language = 'all']) {
    final clean = cleanTerm(uploader);
    return 'https://$domain/uploader/$clean-$language.nozomi';
  }

  /// 특정 태그별 작품 목록 URL 생성 (예: 'female:big breasts' -> 'tag/female:big%20breasts-all.nozomi')
  static String getTagIndexUrl(String tag, [String language = 'all']) {
    var raw = tag.trim();
    if (raw.toLowerCase().startsWith('tag:')) {
      raw = raw.substring(4).trim();
    }
    final cleanTag = cleanTerm(raw);
    return 'https://$domain/tag/$cleanTag-$language.nozomi';
  }

  /// 태그 검색을 스마트하게 처리하는 페처:
  /// 네임스페이스가 없는 일반 태그인 경우 female -> male -> 일반 순으로 자동 Fallback 탐색합니다.
  static Future<List<int>> fetchTagGalleryIds(
    String tag,
    int page, {
    int pageSize = 25,
    String language = 'all',
  }) async {
    var raw = tag.trim();
    if (raw.toLowerCase().startsWith('tag:')) {
      raw = raw.substring(4).trim();
    }

    final lower = raw.toLowerCase();
    // 1) 이미 female: 또는 male: 네임스페이스가 명시된 경우
    if (lower.startsWith('female:') || lower.startsWith('male:')) {
      return await fetchGalleryIds(
        getTagIndexUrl(raw, language),
        page,
        pageSize: pageSize,
      );
    }

    // 2) 네임스페이스가 없는 경우: Hitomi의 90% 이상인 female: 태그 우선 시도
    final femaleIds = await fetchGalleryIds(
      getTagIndexUrl('female:$raw', language),
      page,
      pageSize: pageSize,
    );
    if (femaleIds.isNotEmpty) return femaleIds;

    // 3) male: 태그 시도
    final maleIds = await fetchGalleryIds(
      getTagIndexUrl('male:$raw', language),
      page,
      pageSize: pageSize,
    );
    if (maleIds.isNotEmpty) return maleIds;

    // 4) 일반 태그(중성 태그) 시도
    return await fetchGalleryIds(
      getTagIndexUrl(raw, language),
      page,
      pageSize: pageSize,
    );
  }
}
