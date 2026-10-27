// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:violet/log/log.dart';

/// Hitomi 공식 알파벳별 전체 작가/그룹 풀(allartists / allgroups)을
/// 온디맨드로 로컬에 영구 캐싱하여 누락 없는 태그 자동완성을 지원하는 카탈로그 매니저.
class HitomiTagCatalog {
  /// 국내 통신사 SNI 차단을 우회하기 위한 Hitomi 공식 서버 IP 목록
  static const List<String> _hitomiIps = [
    '216.230.225.130',
    '66.187.78.242',
  ];

  /// 전체 알파벳 식별자 키 목록
  static const List<String> allCharKeys = [
    '123', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
    'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
  ];

  /// 인메모리 알파벳 캐시 (char -> 작가 목록)
  static final Map<String, List<String>> _artistsMemoryCache = {};
  /// 인메모리 알파벳 캐시 (char -> 그룹 목록)
  static final Map<String, List<String>> _groupsMemoryCache = {};

  /// 작가별 작품 수 온라인 캐시 (이름 -> 작품 수)
  static final Map<String, int> _artistCounts = {};
  /// 그룹별 작품 수 온라인 캐시 (이름 -> 작품 수)
  static final Map<String, int> _groupCounts = {};

  static bool _isPreloading = false;

  /// 온라인 카탈로그에서 추출한 작품 수 반환
  static int getCount(String type, String name) {
    final clean = name.trim().toLowerCase();
    final space = clean.replaceAll('_', ' ');
    final under = clean.replaceAll(' ', '_');

    final map = type.toLowerCase() == 'group' ? _groupCounts : _artistCounts;
    return map[clean] ?? map[space] ?? map[under] ?? 0;
  }

  /// 로컬 파일 캐시 디렉터리 경로 취득
  static Future<Directory> _getCatalogDirectory() async {
    final baseDir = Platform.environment.containsKey('FLUTTER_TEST')
        ? Directory.current.path
        : (await getApplicationDocumentsDirectory()).path;
    final dir = Directory('$baseDir/catalog');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 검색어의 첫 글자 키 취득 ('a'~'z' 또는 '123')
  static String getCharKey(String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return '123';
    final first = clean[0];
    if (RegExp(r'[a-z]').hasMatch(first)) {
      return first;
    }
    return '123';
  }

  /// 이미 로컬 디스크에 존재하는 모든 알파벳 캐시 파일들을 메모리로 적재
  static Future<void> _loadAllCachedFromDisk(String type) async {
    try {
      final dir = await _getCatalogDirectory();
      final prefix = type == 'artist' ? 'artists_' : 'groups_';
      final memCache = type == 'artist' ? _artistsMemoryCache : _groupsMemoryCache;

      if (!dir.existsSync()) return;
      final files = dir.listSync().whereType<File>();
      for (final file in files) {
        final filename = file.uri.pathSegments.last;
        if (filename.startsWith(prefix) && filename.endsWith('.json')) {
          final charKey = filename.substring(prefix.length, filename.length - 5);
          if (!memCache.containsKey(charKey)) {
            try {
              final text = await file.readAsString();
              final list = (jsonDecode(text) as List).cast<String>();
              memCache[charKey] = list;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }

  /// 백그라운드에서 모든 알파벳 카탈로그(A~Z, 123)를 사전에 다운로드하여 영구 캐싱
  static Future<void> preloadAllCatalogs() async {
    if (_isPreloading) return;
    _isPreloading = true;

    try {
      await _loadAllCachedFromDisk('artist');
      await _loadAllCachedFromDisk('group');

      // 아직 로컬에 없는 알파벳만 순차/병렬 다운로드 (네트워크 과부하 방지를 위해 3개씩 청크)
      final missingArtists = allCharKeys.where((k) => !_artistsMemoryCache.containsKey(k)).toList();
      for (int i = 0; i < missingArtists.length; i += 3) {
        final chunk = missingArtists.sublist(i, (i + 3 < missingArtists.length) ? i + 3 : missingArtists.length);
        await Future.wait(chunk.map((k) => loadArtists(k)));
        await Future.delayed(const Duration(milliseconds: 100));
      }

      final missingGroups = allCharKeys.where((k) => !_groupsMemoryCache.containsKey(k)).toList();
      for (int i = 0; i < missingGroups.length; i += 3) {
        final chunk = missingGroups.sublist(i, (i + 3 < missingGroups.length) ? i + 3 : missingGroups.length);
        await Future.wait(chunk.map((k) => loadGroups(k)));
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      Logger.info('[HitomiTagCatalog] Preload exception: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// 특정 알파벳의 전체 작가 목록 반환 (메모리 -> 로컬 디스크 -> 온라인 온디맨드 1회 다운로드)
  static Future<List<String>> loadArtists(String charKey) async {
    if (_artistsMemoryCache.containsKey(charKey)) {
      return _artistsMemoryCache[charKey]!;
    }

    final dir = await _getCatalogDirectory();
    final file = File('${dir.path}/artists_$charKey.json');

    if (file.existsSync()) {
      try {
        final text = await file.readAsString();
        final list = (jsonDecode(text) as List).cast<String>();
        _artistsMemoryCache[charKey] = list;
        return list;
      } catch (e) {
        Logger.warning('[HitomiTagCatalog] Failed to read cached artists_$charKey: $e');
      }
    }

    // 온라인에서 알파벳 목록 1회 온디맨드 다운로드
    final fetched = await _fetchCatalogFromWeb('artist', charKey);
    if (fetched.isNotEmpty) {
      _artistsMemoryCache[charKey] = fetched;
      try {
        await file.writeAsString(jsonEncode(fetched));
      } catch (e) {
        Logger.warning('[HitomiTagCatalog] Failed to save artists_$charKey: $e');
      }
      return fetched;
    }

    return [];
  }

  /// 특정 알파벳의 전체 그룹 목록 반환 (메모리 -> 로컬 디스크 -> 온라인 온디맨드 1회 다운로드)
  static Future<List<String>> loadGroups(String charKey) async {
    if (_groupsMemoryCache.containsKey(charKey)) {
      return _groupsMemoryCache[charKey]!;
    }

    final dir = await _getCatalogDirectory();
    final file = File('${dir.path}/groups_$charKey.json');

    if (file.existsSync()) {
      try {
        final text = await file.readAsString();
        final list = (jsonDecode(text) as List).cast<String>();
        _groupsMemoryCache[charKey] = list;
        return list;
      } catch (e) {
        Logger.warning('[HitomiTagCatalog] Failed to read cached groups_$charKey: $e');
      }
    }

    // 온라인에서 알파벳 목록 1회 온디맨드 다운로드
    final fetched = await _fetchCatalogFromWeb('group', charKey);
    if (fetched.isNotEmpty) {
      _groupsMemoryCache[charKey] = fetched;
      try {
        await file.writeAsString(jsonEncode(fetched));
      } catch (e) {
        Logger.warning('[HitomiTagCatalog] Failed to save groups_$charKey: $e');
      }
      return fetched;
    }

    return [];
  }

  /// 검색어(prefix)와 일치하는 작가 목록 검색:
  /// 1. 타깃 알파벳 온디맨드 로드 (접두사 일치 보장)
  /// 2. 이미 로컬에 캐시된 전체 알파벳 카탈로그 메모리 로드
  /// 3. 정렬 순서: 완전 접두사 일치 > 단어 단위 접두사 일치(kawasaki tadataka) > 단순 포함 일치
  static Future<List<String>> searchArtists(String prefix) async {
    final clean = prefix.trim().toLowerCase().replaceAll('_', ' ');
    if (clean.isEmpty) return [];

    final charKey = getCharKey(clean);
    await loadArtists(charKey);
    await _loadAllCachedFromDisk('artist');

    final startsWithMatches = <String>[];
    final wordBoundaryMatches = <String>[];
    final containsMatches = <String>[];
    final seen = <String>{};

    for (final artistList in _artistsMemoryCache.values) {
      for (final artist in artistList) {
        if (!seen.add(artist)) continue;
        final aLower = artist.toLowerCase();
        if (aLower.startsWith(clean)) {
          startsWithMatches.add(artist);
        } else if (aLower.split(RegExp(r'[\s_]+')).any((w) => w.startsWith(clean))) {
          wordBoundaryMatches.add(artist);
        } else if (aLower.contains(clean)) {
          containsMatches.add(artist);
        }
      }
    }

    return [...startsWithMatches, ...wordBoundaryMatches, ...containsMatches];
  }

  /// 검색어(prefix)와 일치하는 그룹 목록 검색:
  /// 1. 타깃 알파벳 온디맨드 로드 (접두사 일치 보장)
  /// 2. 이미 로컬에 캐시된 전체 알파벳 카탈로그 메모리 로드
  /// 3. 정렬 순서: 완전 접두사 일치 > 단어 단위 접두사 일치 > 단순 포함 일치
  static Future<List<String>> searchGroups(String prefix) async {
    final clean = prefix.trim().toLowerCase().replaceAll('_', ' ');
    if (clean.isEmpty) return [];

    final charKey = getCharKey(clean);
    await loadGroups(charKey);
    await _loadAllCachedFromDisk('group');

    final startsWithMatches = <String>[];
    final wordBoundaryMatches = <String>[];
    final containsMatches = <String>[];
    final seen = <String>{};

    for (final groupList in _groupsMemoryCache.values) {
      for (final group in groupList) {
        if (!seen.add(group)) continue;
        final gLower = group.toLowerCase();
        if (gLower.startsWith(clean)) {
          startsWithMatches.add(group);
        } else if (gLower.split(RegExp(r'[\s_]+')).any((w) => w.startsWith(clean))) {
          wordBoundaryMatches.add(group);
        } else if (gLower.contains(clean)) {
          containsMatches.add(group);
        }
      }
    }

    return [...startsWithMatches, ...wordBoundaryMatches, ...containsMatches];
  }

  /// SNI 차단 우회(Direct IP + Host 헤더)를 통해 Hitomi 공식 allartists/allgroups 다운로드
  static Future<List<String>> _fetchCatalogFromWeb(String type, String charKey) async {
    final path = type == 'artist' ? 'allartists-$charKey.html' : 'allgroups-$charKey.html';
    final regex = type == 'artist'
        ? RegExp(r'href="/artist/([^"-]+)-all\.html">([^<]+)</a>(?:\s*\(([0-9]+)\))?')
        : RegExp(r'href="/group/([^"-]+)-all\.html">([^<]+)</a>(?:\s*\(([0-9]+)\))?');

    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 5);

    for (final ip in _hitomiIps) {
      try {
        final uri = Uri.parse('https://$ip/$path');
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 5));
        request.headers.set('Host', 'hitomi.la');
        request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
        request.headers.set('Referer', 'https://hitomi.la/');

        final response = await request.close().timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final matches = regex.allMatches(body);
          final result = <String>{};
          final targetCounts = type == 'artist' ? _artistCounts : _groupCounts;
          for (final m in matches) {
            final raw = m.group(1);
            if (raw != null && raw.trim().isNotEmpty) {
              String decoded;
              try {
                decoded = Uri.decodeComponent(raw.trim());
              } catch (_) {
                decoded = raw.trim();
              }
              result.add(decoded);

              final countStr = m.group(3);
              if (countStr != null) {
                final count = int.tryParse(countStr) ?? 0;
                if (count > 0) {
                  final lower = decoded.toLowerCase();
                  targetCounts[lower] = count;
                  targetCounts[lower.replaceAll(' ', '_')] = count;
                  targetCounts[lower.replaceAll('_', ' ')] = count;
                }
              }
            }
          }
          client.close();
          return result.toList();
        }
      } catch (e) {
        Logger.info('[HitomiTagCatalog] IP $ip fetch failed: $e');
      }
    }

    client.close();
    return [];
  }
}
