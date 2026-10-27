// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:violet/algorithm/distance.dart';
import 'package:violet/component/hitomi/artists.dart';
import 'package:violet/component/hitomi/displayed_tag.dart';
import 'package:violet/component/hitomi/tag_catalog.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/component/hitomi/tag_translate.dart';
import 'package:violet/database/database.dart';
import 'package:violet/log/log.dart';
import 'package:violet/variables.dart';

// This is used for estimation similiar Aritst/Group/Uplaoder with each others.
class HentaiIndex {
  // Tag Group, <Tag, Article Count>
  static Map<String, dynamic>? tagCount;
  // Tag, Index
  // Map<String, int>
  static Map<String, dynamic> tagIndex = <String, dynamic>{};
  // Artist, <Tag Index, Count>
  // Map<String, Map<String, int>>
  static Map<String, dynamic> tagArtist = <String, dynamic>{};
  static Map<String, dynamic> tagGroup = <String, dynamic>{};
  static Map<String, dynamic> tagUploader = <String, dynamic>{};
  static Map<String, dynamic> tagSeries = <String, dynamic>{};
  static Map<String, dynamic> tagCharacter = <String, dynamic>{};
  // Series, <Character, Count>
  // Map<String, Map<String, int>>
  static Map<String, dynamic>? characterSeries;
  // Unmap of character series
  // Character, <Series, Count>
  // Map<String, Map<String, int>>
  static Map<String, dynamic>? seriesCharacter;
  // Series, <Series, Count>
  // Map<String, Map<String, int>>
  static Map<String, dynamic>? seriesSeries;
  // Character, <Character, Count>
  // Map<String, Map<String, int>>
  static Map<String, dynamic>? characterCharacter;
  // Tag, [<Tag, Similarity>]
  static Map<String, dynamic> relatedTag = <String, dynamic>{};

  /// 지원되는 표준 언어 목록 (영문 식별자, 한글 표기)
  static const supportedLanguages = <(String, String)>[
    ('korean', '한국어'),
    ('japanese', '일본어'),
    ('english', '영어'),
    ('chinese', '중국어'),
    ('spanish', '스페인어'),
    ('french', '프랑스어'),
    ('german', '독일어'),
    ('russian', '러시아어'),
  ];

  static Set<String>? _builtinArtists;
  static Set<String> get builtinArtists {
    if (_builtinArtists != null) return _builtinArtists!;
    final set = <String>{};
    try {
      for (final list in Artists.collection.values) {
        if (list is List) {
          for (final item in list) {
            if (item is String && item.trim().isNotEmpty) {
              set.add(item.trim());
            }
          }
        }
      }
    } catch (_) {}
    _builtinArtists = set;
    return set;
  }

  static File _resolveFile(String basePath, String filename) {
    final sub = Platform.isAndroid ? '/data' : '';
    final f1 = File('$basePath$sub/$filename');
    if (f1.existsSync()) return f1;
    final f2 = File('$basePath/$filename');
    if (f2.existsSync()) return f2;
    return f1;
  }

  static Future<void> init() async {
    await _loadIndexes();
    await _loadCountMap();
    HitomiTagCatalog.preloadAllCatalogs().ignore();
  }

  static Future<void> _loadIndexes() async {
    final directory = await getApplicationDocumentsDirectory();

    // No data on first run.
    final path2 = _resolveFile(directory.path, 'tag-artist.json');
    if (!await path2.exists()) return;
    tagArtist = jsonDecode(await path2.readAsString());
    final path3 = _resolveFile(directory.path, 'tag-group.json');
    tagGroup = jsonDecode(await path3.readAsString());
    final path4 = _resolveFile(directory.path, 'tag-index.json');
    tagIndex = jsonDecode(await path4.readAsString());
    final path5 = _resolveFile(directory.path, 'tag-uploader.json');
    tagUploader = jsonDecode(await path5.readAsString());
    try {
      final path6 = _resolveFile(directory.path, 'tag-series.json');
      tagSeries = jsonDecode(await path6.readAsString());
      final path7 = _resolveFile(directory.path, 'tag-character.json');
      tagCharacter = jsonDecode(await path7.readAsString());
      final path8 = _resolveFile(directory.path, 'character-series.json');
      characterSeries = jsonDecode(await path8.readAsString());
      final path9 = _resolveFile(directory.path, 'series-character.json');
      seriesCharacter = jsonDecode(await path9.readAsString());

      final path10 = _resolveFile(directory.path, 'character-character.json');
      characterCharacter = jsonDecode(await path10.readAsString());
      final path11 = _resolveFile(directory.path, 'series-series.json');
      seriesSeries = jsonDecode(await path11.readAsString());
    } catch (e, st) {
      Logger.error(
        '[Hitomi-Indexes] E: $e\n'
        '$st',
      );
    }

    var relatedData =
        json.decode(
              await rootBundle.loadString(
                'assets/locale/tag/related-tag-${TagTranslate.defaultLanguage}.json',
              ),
            )
            as List<dynamic>;
    relatedTag = <String, dynamic>{};
    for (var element in relatedData) {
      var kv = (element as Map<String, dynamic>).entries.first;
      relatedTag[kv.key] = kv.value;
    }
  }

  static Future<void> _loadCountMap() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final file = File(join(Directory.current.path, 'test/db/index.json'));
      tagCount = jsonDecode(await file.readAsString());
    } else {
      final directory = await getApplicationDocumentsDirectory();
      final path = _resolveFile(directory.path, 'index.json');
      if (!await path.exists()) return;
      final text = path.readAsStringSync();
      tagCount = jsonDecode(text);
    }

    // split `tag:female:` and `tag:male:` to `female:` and `male:`
    if (tagCount != null && tagCount!.containsKey('tag')) {
      final tags = tagCount!['tag'] as Map<String, dynamic>;
      final femaleTags = tags.entries
          .where((e) => e.key.startsWith('female:'))
          .map((e) => MapEntry(e.key.split(':')[1], e.value))
          .toList();
      final maleTags = tags.entries
          .where((e) => e.key.startsWith('male:'))
          .map((e) => MapEntry(e.key.split(':')[1], e.value))
          .toList();
      tagCount!['female'] = Map.fromEntries(femaleTags);
      tagCount!['male'] = Map.fromEntries(maleTags);

      tags.removeWhere(
        (tag, _) => tag.startsWith('female:') || tag.startsWith('male:'),
      );
    }
  }

  static Future<void> loadCountMapIfRequired() async {
    if (tagCount == null) {
      await _loadCountMap();
    }
  }

  static int getArticleCount(String classification, String name) {
    if (tagCount == null) {
      try {
        final path = _resolveFile(
          Variables.applicationDocumentsDirectory,
          'index.json',
        );
        if (path.existsSync()) {
          final text = path.readAsStringSync();
          tagCount = jsonDecode(text);
        }
      } catch (_) {}
    }

    if (tagCount != null && tagCount!.containsKey(classification)) {
      final map = tagCount![classification];
      if (map is Map) {
        final clean = name.trim();
        final lower = clean.toLowerCase();
        final space = lower.replaceAll('_', ' ');
        final under = lower.replaceAll(' ', '_');

        final dynamic val = map[clean] ?? map[lower] ?? map[space] ?? map[under];
        if (val is num && val > 0) {
          return val.toInt();
        }
      }
    }

    final catalogCount = HitomiTagCatalog.getCount(classification, name);
    if (catalogCount > 0) {
      return catalogCount;
    }

    return 0;
  }

  static Future<List<(DisplayedTag, int)>> queryAutoComplete(
    String prefix, [
    bool useTranslated = false,
  ]) async {
    await loadCountMapIfRequired();

    prefix = prefix.toLowerCase().replaceAll('_', ' ');

    if (prefix.contains(':') && prefix.split(':')[0] != 'random') {
      return await _queryAutoCompleteWithTagmap(prefix, useTranslated);
    }

    return await _queryAutoCompleteFullSearch(prefix, useTranslated);
  }

  static Future<List<(DisplayedTag, int)>> _queryAutoCompleteWithTagmap(
    String prefix,
    bool useTranslated,
  ) async {
    final groupOrig = prefix.split(':')[0];
    final group = _normalizeTagPrefix(groupOrig);
    final name = prefix.split(':').last;

    final results = <(DisplayedTag, int)>[];

    // 언어(lang / language) 태그 자동완성 특화:
    // 로컬 DB 인덱싱이 특정 언어로만 제한되어 있더라도
    // 언제든 다른 언어를 검색하고 선택할 수 있도록 표준 지원 언어 전체를 매칭/추천
    if (group == 'lang') {
      final nameCountsMap = (tagCount != null && tagCount!.containsKey('lang'))
          ? (tagCount!['lang'] as Map<dynamic, dynamic>)
          : <dynamic, dynamic>{};

      final cleanName = name.trim().toLowerCase();

      for (final item in supportedLanguages) {
        final langCode = item.$1;
        final langKor = item.$2;
        final count = (nameCountsMap[langCode] ?? 0) as int;

        if (cleanName.isEmpty ||
            langCode.contains(cleanName) ||
            langKor.contains(cleanName)) {
          results.add((
            DisplayedTag(
              group: 'lang',
              name: langCode,
              translated: langKor,
            ),
            count,
          ));
        }
      }

      nameCountsMap.forEach((key, value) {
        final kStr = key.toString();
        if (!supportedLanguages.any((e) => e.$1 == kStr)) {
          if (cleanName.isEmpty || kStr.toLowerCase().contains(cleanName)) {
            results.add((
              DisplayedTag(group: 'lang', name: kStr),
              (value as num).toInt(),
            ));
          }
        }
      });

      results.sort((a, b) => b.$2.compareTo(a.$2));
      return results;
    }

    final seen = <String>{};
    if (tagCount != null && tagCount!.containsKey(group)) {
      final nameCountsMap = tagCount![group] as Map<dynamic, dynamic>;
      // 1) TagTranslate를 통해 영문/한글 매칭 결과 추가 (번역명 포함)
      final transMatches = TagTranslate.containsTotal(name)
          .where((e) => e.group! == group || (group == 'tag' && (e.group == 'female' || e.group == 'male')));
      for (final tag in transMatches) {
        final key = '${tag.group}:${tag.name}';
        if (!seen.contains(key)) {
          seen.add(key);
          final count = (nameCountsMap[tag.name] ?? 0) as int;
          results.add((tag, count));
        }
      }

      // 2) tagCount 영문 직접 매칭 추가 (번역에 없는 태그이거나 추가 매칭)
      nameCountsMap.entries
          .where((e) => e.key.toString().toLowerCase().contains(name.toLowerCase()))
          .forEach((e) {
            final key = '$group:${e.key}';
            if (!seen.contains(key)) {
              seen.add(key);
              results.add((
                DisplayedTag(
                  group: group,
                  name: e.key.toString(),
                  translated: TagTranslate.of(group, e.key.toString()),
                ),
                (e.value as num).toInt(),
              ));
            }
          });
    }

    // 3) 아티스트/그룹의 경우 Hitomi 카탈로그 및 내장 사전 매칭
    if (group == 'artist') {
      _appendFromBuiltinArtists(name, results, seen);
      await _appendFromCatalog('artist', name, results, seen);
    } else if (group == 'group') {
      await _appendFromCatalog('group', name, results, seen);
    }

    // 4) 로컬 SQLite DB(HitomiColumnModel) 실시간 조회 폴백
    if (group == 'artist' || group == 'group' || group == 'series' || group == 'character' || group == 'uploader') {
      await _appendFromDatabase(group, name, results, seen);
    }

    // tagCount가 없거나 매칭 결과가 없을 때 TagTranslate에서 직접 보충
    if (results.isEmpty) {
      final matches = TagTranslate.containsTotal(name)
          .where((e) => e.group == group || (group == 'tag' && (e.group == 'female' || e.group == 'male')));
      for (final tag in matches) {
        final key = '${tag.group}:${tag.name}';
        if (!seen.contains(key)) {
          seen.add(key);
          results.add((tag, 0));
        }
      }
    }

    _sortAutoCompleteResults(results, name, isExplicitGroupSearch: true);
    return results;
  }

  static Future<List<(DisplayedTag, int)>> _queryAutoCompleteFullSearch(
    String prefix,
    bool useTranslated,
  ) async {
    final results = <(DisplayedTag, int)>[];
    final seen = <String>{};

    // 언어 관련 검색어인 경우 lang: 태그 추천도 추가 (예: '일본어', 'korean' 등)
    final cleanPrefix = prefix.trim().toLowerCase();
    if (cleanPrefix.isNotEmpty) {
      for (final item in supportedLanguages) {
        if (item.$1.contains(cleanPrefix) || item.$2.contains(cleanPrefix)) {
          final key = 'lang:${item.$1}';
          if (!seen.contains(key)) {
            seen.add(key);
            int count = 0;
            if (tagCount != null &&
                tagCount!.containsKey('lang') &&
                tagCount!['lang'].containsKey(item.$1)) {
              count = (tagCount!['lang'][item.$1] as num).toInt();
            }
            results.add((
              DisplayedTag(
                group: 'lang',
                name: item.$1,
                translated: item.$2,
              ),
              count,
            ));
          }
        }
      }
    }

    // 1. TagTranslate를 활용한 한글/영문 매칭 (초성, 자모 분해, 완성형 모두 지원)
    final transList = TagTranslate.containsTotal(prefix);
    for (final tag in transList) {
      final key = '${tag.group}:${tag.name}';
      if (seen.contains(key)) continue;
      seen.add(key);

      int count = 0;
      if (tagCount != null &&
          tagCount!.containsKey(tag.group) &&
          tagCount![tag.group].containsKey(tag.name)) {
        count = (tagCount![tag.group][tag.name] as num).toInt();
      }
      results.add((tag, count));
    }

    // 2. tagCount가 있는 경우 영문 이름으로도 추가 매칭
    if (tagCount != null) {
      if (tagCount!.containsKey('tag')) {
        tagCount!['tag'].forEach((group, count) {
          if (group.contains(':')) {
            final subGroup = group.split(':');
            if (subGroup[1].contains(prefix)) {
              final key = '${subGroup[0]}:$group';
              if (!seen.contains(key)) {
                seen.add(key);
                results.add((DisplayedTag(group: subGroup[0], name: group), (count as num).toInt()));
              }
            }
          } else if (group.contains(prefix)) {
            final key = 'tag:$group';
            if (!seen.contains(key)) {
              seen.add(key);
              results.add((DisplayedTag(group: 'tag', name: group), (count as num).toInt()));
            }
          }
        });
      }

      tagCount!.forEach((group, value) {
        if (group != 'tag' && value is Map) {
          value.forEach((name, count) {
            final nameStr = name.toString();
            if (nameStr.toLowerCase().contains(prefix)) {
              final key = '$group:$nameStr';
              if (!seen.contains(key)) {
                seen.add(key);
                results.add((
                  DisplayedTag(
                    group: group,
                    name: nameStr,
                    translated: TagTranslate.of(group, nameStr),
                  ),
                  (count as num).toInt(),
                ));
              }
            }
          });
        }
      });
    }

    // 3. 내장 아티스트 사전 매칭
    _appendFromBuiltinArtists(prefix, results, seen);

    // 4. Hitomi 공식 작가/그룹 카탈로그 매칭 (온디맨드 로컬 캐시)
    // 단문자(1~2자) 일반 검색 시 무명/0작품 카탈로그 항목이 대량 유입되는 것을 방지하기 위해 최소 3자 이상이거나 count > 0인 항목만 허용
    if (cleanPrefix.length >= 3) {
      await _appendFromCatalog('artist', prefix, results, seen);
      await _appendFromCatalog('group', prefix, results, seen);
    } else {
      await _appendFromCatalog('artist', prefix, results, seen, minCount: 1);
      await _appendFromCatalog('group', prefix, results, seen, minCount: 1);
    }

    // 5. 로컬 SQLite DB(HitomiColumnModel) 실시간 조회 폴백
    await _appendFromDatabase('artist', prefix, results, seen);
    await _appendFromDatabase('group', prefix, results, seen);

    _sortAutoCompleteResults(results, prefix);
    return results;
  }

  static void _appendFromBuiltinArtists(
    String query,
    List<(DisplayedTag, int)> results,
    Set<String> seen,
  ) {
    final clean = query.trim().toLowerCase().replaceAll('_', ' ');
    if (clean.isEmpty) return;

    for (final artist in builtinArtists) {
      if (artist.toLowerCase().contains(clean)) {
        final key = 'artist:$artist';
        if (!seen.contains(key)) {
          seen.add(key);
          results.add((
            DisplayedTag(group: 'artist', name: artist),
            0,
          ));
        }
      }
    }
  }

  static Future<void> _appendFromCatalog(
    String group,
    String query,
    List<(DisplayedTag, int)> results,
    Set<String> seen, {
    int minCount = 0,
  }) async {
    try {
      final clean = query.trim().replaceAll('_', ' ');
      if (clean.isEmpty) return;

      final matches = group == 'artist'
          ? await HitomiTagCatalog.searchArtists(clean)
          : await HitomiTagCatalog.searchGroups(clean);

      for (final item in matches) {
        final key = '$group:$item';
        if (!seen.contains(key)) {
          seen.add(key);
          int count = 0;
          if (tagCount != null &&
              tagCount!.containsKey(group) &&
              tagCount![group].containsKey(item)) {
            count = (tagCount![group][item] as num).toInt();
          }
          if (count < minCount) continue;
          results.add((
            DisplayedTag(
              group: group,
              name: item,
              translated: TagTranslate.of(group, item),
            ),
            count,
          ));
        }
      }
    } catch (_) {}
  }

  static Future<void> _appendFromDatabase(
    String group,
    String query,
    List<(DisplayedTag, int)> results,
    Set<String> seen,
  ) async {
    try {
      final columnMap = {
        'artist': 'Artists',
        'group': 'Groups',
        'series': 'Series',
        'character': 'Characters',
        'uploader': 'Uploader',
      };
      final column = columnMap[group];
      if (column == null) return;

      final clean = query.trim().replaceAll('_', ' ');
      if (clean.isEmpty) return;

      if (Settings.databaseType.value == 'dummy') return;

      final db = await DataBaseManager.getInstance();
      if (db.db == null || !db.db!.isOpen) return;
      final escaped = clean.replaceAll("'", "''");
      final rawResults = await db.query(
        "SELECT $column FROM HitomiColumnModel WHERE $column LIKE '%$escaped%' LIMIT 100",
      );

      final tokenCounts = <String, int>{};
      for (final row in rawResults) {
        final val = row[column];
        if (val == null) continue;
        final parts = val.toString().split('|');
        for (var part in parts) {
          part = part.trim();
          if (part.isEmpty) continue;
          if (part.toLowerCase().contains(clean.toLowerCase())) {
            tokenCounts[part] = (tokenCounts[part] ?? 0) + 1;
          }
        }
      }

      for (final entry in tokenCounts.entries) {
        final key = '$group:${entry.key}';
        if (!seen.contains(key)) {
          seen.add(key);
          results.add((
            DisplayedTag(
              group: group,
              name: entry.key,
              translated: TagTranslate.of(group, entry.key),
            ),
            entry.value,
          ));
        }
      }
    } catch (_) {}
  }

  /// 동기적으로 메모리에 있는 태그 및 아티스트, 그룹, 시리즈를 0ms 만에 검색하는 메서드 (FilterPage 연동용)
  static List<(DisplayedTag, int)> searchTagsSync(String query) {
    final clean = query.trim().toLowerCase().replaceAll('_', ' ');
    if (clean.isEmpty) return const [];

    final results = <(DisplayedTag, int)>[];
    final seen = <String>{};

    // 1. TagTranslate (일반 태그, 시리즈, 캐릭터 등)
    final transMatches = TagTranslate.containsTotal(clean);
    for (final tag in transMatches) {
      final key = '${tag.group}:${tag.name}';
      if (!seen.contains(key)) {
        seen.add(key);
        int count = 0;
        if (tagCount != null &&
            tagCount!.containsKey(tag.group) &&
            tagCount![tag.group].containsKey(tag.name)) {
          count = (tagCount![tag.group][tag.name] as num).toInt();
        }
        results.add((tag, count));
      }
    }

    // 2. tagCount 메모리 맵 (artist, group, uploader, type 등 전체 그룹)
    if (tagCount != null) {
      tagCount!.forEach((group, map) {
        if (map is Map) {
          map.forEach((k, v) {
            final kStr = k.toString();
            if (kStr.toLowerCase().contains(clean)) {
              final key = '$group:$kStr';
              if (!seen.contains(key)) {
                seen.add(key);
                results.add((
                  DisplayedTag(
                    group: group,
                    name: kStr,
                    translated: TagTranslate.of(group, kStr),
                  ),
                  (v as num).toInt(),
                ));
              }
            }
          });
        }
      });
    }

    // 3. 내장 아티스트 사전 (Artists.collection)
    for (final artist in builtinArtists) {
      if (artist.toLowerCase().contains(clean)) {
        final key = 'artist:$artist';
        if (!seen.contains(key)) {
          seen.add(key);
          results.add((DisplayedTag(group: 'artist', name: artist), 0));
        }
      }
    }

    _sortAutoCompleteResults(results, clean);
    return results;
  }

  /// 태그 자동완성 스마트 랭킹 정렬 알고리즘:
  /// 1. 일치도 (완전 일치 > 접두어 일치 > 단어 시작 일치 > 중간 포함)
  /// 2. 태그 그룹 우선순위 (tag, female, male > artist, group > lang > series > character)
  /// 3. 작품 수 (인기도 가산)
  /// 4. 이름 길이 (짧은 핵심 태그 우선)
  static void _sortAutoCompleteResults(
    List<(DisplayedTag, int)> results,
    String query, {
    bool isExplicitGroupSearch = false,
  }) {
    final cleanQuery = query.trim().toLowerCase();

    int scoreTag((DisplayedTag, int) item) {
      final tag = item.$1;
      final count = item.$2;
      final name = (tag.name ?? '').toLowerCase();
      final translated = (tag.translated ?? '').toLowerCase();
      final group = (tag.group ?? '').toLowerCase();

      int score = 0;

      // 1. 일치 방식 점수 (Match Quality)
      if (name == cleanQuery) {
        score += 20000;
      } else if (translated == cleanQuery) {
        score += 18000;
      } else if (name.startsWith(cleanQuery)) {
        score += 15000;
      } else if (translated.startsWith(cleanQuery)) {
        score += 13000;
      } else if (name.split(RegExp(r'[\s_]+')).any((word) => word.startsWith(cleanQuery))) {
        score += 10000;
      } else {
        score += 1000;
      }

      final isWordMatch = name.split(RegExp(r'[\s_]+')).any((word) => word.startsWith(cleanQuery));

      // 2. 그룹 우선순위 (Group Priority)
      if (isExplicitGroupSearch) {
        switch (group) {
          case 'artist':
          case 'group':
            score += name.startsWith(cleanQuery) ? 2000 : (isWordMatch ? 1500 : 1000);
            break;
          default:
            score += 500;
            break;
        }
      } else {
        // 일반 검색 시
        switch (group) {
          case 'tag':
          case 'female':
          case 'male':
            score += 1500;
            break;
          case 'lang':
          case 'language':
            score += 1200;
            break;
          case 'artist':
          case 'group':
            score += isWordMatch ? 1800 : 600;
            break;
          case 'series':
            score += 300;
            break;
          case 'character':
            score += 100;
            break;
          default:
            score += 50;
            break;
        }
      }

      // 3. 인기도 / 작품 수 (Count) - 작품 수가 있는 검증된 태그를 최우선 배치
      if (count > 0) {
        score += 8000;
        score += (count > 2000 ? 2000 : count);
      } else {
        // 작품 수 0건이면서 2자 이하 초단문자인 미검증 단어는 큰 감점
        if (name.length <= 2) {
          score -= 10000;
        }
      }

      // 4. 이름 길이 패널티 (짧은 핵심 단어 우선)
      if (name.isNotEmpty) {
        score -= name.length * 2;
      }

      return score;
    }

    results.sort((a, b) => scoreTag(b).compareTo(scoreTag(a)));
  }

  static Future<List<(DisplayedTag, int)>> queryAutoCompleteFuzzy(
    String prefix, [
    bool useTranslated = false,
  ]) async {
    await loadCountMapIfRequired();

    prefix = prefix.toLowerCase().replaceAll('_', ' ');

    if (prefix.contains(':')) {
      final groupOrig = prefix.split(':')[0];
      final group = _normalizeTagPrefix(groupOrig);
      final name = prefix.split(':').last;

      if (group == 'lang') {
        return await _queryAutoCompleteWithTagmap(prefix, useTranslated);
      }

      // <Tag, Similarity, Count>
      final results = <(DisplayedTag, int, int)>[];
      if (tagCount != null && tagCount!.containsKey(group)) {
        final nameCountsMap = tagCount![group];
        if (!useTranslated) {
          nameCountsMap.forEach((key, value) {
            results.add((
              DisplayedTag(group: group, name: key),
              Distance.levenshteinDistance(
                name.runes.toList(),
                key.runes.toList(),
              ),
              (value as num).toInt(),
            ));
          });
        } else {
          results.addAll(
            TagTranslate.containsFuzzingTotal(name)
                .where(
                  (e) =>
                      e.$1.group! == group &&
                      nameCountsMap.containsKey(e.$1.name),
                )
                .map((e) => (e.$1, e.$2, (nameCountsMap[e.$1.name] as num).toInt())),
          );
        }
      }

      if (results.isEmpty) {
        final fuzzed = TagTranslate.containsFuzzingTotal(name)
            .where((e) => e.$1.group == group)
            .map((e) => (e.$1, e.$2, 0));
        results.addAll(fuzzed);
      }

      if (results.isEmpty && (group == 'artist' || group == 'group' || group == 'series')) {
        return await _queryAutoCompleteWithTagmap(prefix, useTranslated);
      }

      results.sort((a, b) => a.$2.compareTo(b.$2));
      return results.map((e) => (e.$1, e.$3)).toList();
    } else {
      if (tagCount != null && !useTranslated) {
        final results = <(DisplayedTag, int, int)>[];
        tagCount!.forEach((group, value) {
          if (value is Map) {
            value.forEach((name, count) {
              results.add((
                DisplayedTag(group: group, name: name.toString()),
                Distance.levenshteinDistance(
                  prefix.runes.toList(),
                  name.toString().runes.toList(),
                ),
                (count as num).toInt(),
              ));
            });
          }
        });
        results.sort((a, b) => a.$2.compareTo(b.$2));
        return results.map((e) => (e.$1, e.$3)).toList();
      } else {
        final fuzzed = TagTranslate.containsFuzzingTotal(prefix);
        final results = <(DisplayedTag, int, int)>[];
        for (final item in fuzzed) {
          int count = 0;
          if (tagCount != null &&
              tagCount!.containsKey(item.$1.group) &&
              tagCount![item.$1.group].containsKey(item.$1.name)) {
            count = (tagCount![item.$1.group][item.$1.name] as num).toInt();
          }
          results.add((item.$1, count, item.$2));
        }
        results.sort((a, b) => a.$3.compareTo(b.$3));
        return results.map((e) => (e.$1, e.$2)).toList();
      }
    }
  }

  static List<(String, double)> _calculateSimilars(
    Map<String, dynamic> map,
    String artist,
  ) {
    var rr = map[artist];
    var result = <(String, double)>[];

    map.forEach((key, value) {
      if (artist == key) return;
      if (key.toLowerCase() == 'n/a') return;

      var dist = Distance.cosineDistance(rr, value);
      result.add((key, dist));
    });

    result.sort((x, y) => y.$2.compareTo(x.$2));

    return result;
  }

  static List<(String, double)> caclulateSimilarsManual(
    Map<String, dynamic> map,
    Map<String, dynamic> target,
  ) {
    final result = <(String, double)>[];

    map.forEach((key, value) {
      if (key.toLowerCase() == 'n/a') return;

      final dist = Distance.cosineDistance(target, value);
      result.add((key, dist));
    });

    result.sort((x, y) => y.$2.compareTo(x.$2));

    return result;
  }

  static List<(String, double)> calculateSimilarArtists(String artist) {
    return _calculateSimilars(tagArtist, artist);
  }

  static List<(String, double)> calculateSimilarGroups(String group) {
    return _calculateSimilars(tagGroup, group);
  }

  static List<(String, double)> calculateSimilarUploaders(String uploader) {
    return _calculateSimilars(tagUploader, uploader);
  }

  static List<(String, double)> calculateSimilarSeries(String series) {
    return _calculateSimilars(tagSeries, series);
  }

  static List<(String, double)> calculateSimilarCharacter(String character) {
    return _calculateSimilars(tagCharacter, character);
  }

  static List<(String, double)> calculateRelatedCharacterSeries(String series) {
    if (seriesSeries == null) {
      return _calculateSimilars(
        characterSeries!,
        series,
      ).where((element) => element.$2 >= 0.000001).toList();
    } else {
      var ll = (seriesSeries![series] as Map<String, dynamic>).entries
          .map((e) => (e.key, (e.value as int).toDouble()))
          .toList();
      ll.sort((x, y) => y.$2.compareTo(x.$2));
      return ll;
    }
  }

  static List<(String, double)> calculateRelatedSeriesCharacter(
    String character,
  ) {
    if (characterCharacter == null) {
      return _calculateSimilars(
        seriesCharacter!,
        character,
      ).where((element) => element.$2 >= 0.000001).toList();
    } else {
      var ll = (characterCharacter![character] as Map<String, dynamic>).entries
          .map((e) => (e.key, (e.value as num).toDouble()))
          .toList();
      ll.sort((x, y) => y.$2.compareTo(x.$2));
      return ll;
    }
  }

  static List<(String, double)> getRelatedCharacters(String series) {
    if (!characterSeries!.containsKey(series)) {
      return <(String, double)>[];
    }
    var ll = (characterSeries![series] as Map<String, dynamic>).entries
        .map((e) => (e.key, (e.value as num).toDouble()))
        .toList();
    ll.sort((x, y) => y.$2.compareTo(x.$2));
    return ll;
  }

  static List<(String, double)> getRelatedSeries(String character) {
    if (!seriesCharacter!.containsKey(character)) {
      return <(String, double)>[];
    }
    var ll = (seriesCharacter![character] as Map<String, dynamic>).entries
        .map((e) => (e.key, (e.value as num).toDouble()))
        .toList();
    ll.sort((x, y) => y.$2.compareTo(x.$2));
    return ll;
  }

  static List<(String, double)> getRelatedTag(String tag) {
    if (!relatedTag.containsKey(tag)) return <(String, double)>[];
    var ll = (relatedTag[tag] as List<dynamic>)
        .map(
          (e) => (
            (e as Map<String, dynamic>).entries.first.key,
            (e.entries.first.value as num).toDouble(),
          ),
        )
        .toList();
    ll.sort((x, y) => y.$2.compareTo(x.$2));
    return ll;
  }
}

String _normalizeTagPrefix(String pp) {
  switch (pp) {
    case 'tags':
      return 'tag';

    case 'language':
    case 'languages':
      return 'lang';

    case 'artists':
      return 'artist';

    case 'groups':
      return 'group';

    case 'types':
      return 'type';

    case 'characters':
      return 'character';

    case 'classes':
      return 'class';
  }

  return pp;
}
