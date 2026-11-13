// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:violet/database/query.dart';
import 'package:violet/platform/misc.dart';
import 'package:violet/settings/device_type.dart';

class Settings {
  static late final SharedPreferences prefs;

  // Bookmark Git Settings
  static final bookmarkRepository = SettingItem<String>(
    'bookmarkRepository',
    'example/bookmark',
  );
  static final bookmarkHost = SettingItem<String>('bookmarkHost', 'gitee.com');

  // Timeout Settings
  static final ignoreTimeout = SettingItem<bool>('ignoreTimeout', false);

  // Color Settings
  static Color get themeColor => themeWhat.value ? Colors.white : Colors.black;
  static final themeWhat = SettingItem<bool>('themeColor', false);
  static final majorColor = SettingItem<Color>('majorColor', Colors.purple);
  static final majorAccentColor = SettingItem<Color>(
    'majorAccentColor',
    Colors.purpleAccent,
  );
  static final searchResultType = EnumSettingItem<SearchResultType>(
    'searchResultType',
    SearchResultType.values,
    SearchResultType.ultra,
  );
  static final themeFlat = SettingItem<bool>('themeFlat', false);
  static final themeBlack = SettingItem<bool>('themeBlack', false);
  static final useSystemTheme = SettingItem<bool>('useSystemTheme', true);
  static final useTabletMode = SettingItem<bool>('usetabletmode', false);

  // Tag Settings
  static final includeTags = SettingItem<String>('includetags', () {
    final langcode = Platform.localeName.split('_')[0];
    var language = 'lang:english';
    if (langcode == 'ko') {
      language = 'lang:korean';
    } else if (langcode == 'ja') {
      language = 'lang:japanese';
    } else if (langcode.startsWith('zh')) {
      language = 'lang:chinese';
    }
    return '($language)';
  }());
  static final excludeTags = SettingItem<List<String>>('excludetags', []);
  static final blurredTags = SettingItem<List<String>>('blurredtags', []);
  static final favoriteTags = SettingItem<List<String>>('favoritetags', []);
  static final language = SettingItem<String>('language', '');
  static final translateTags = SettingItem<bool>('translatetags', false);

  static Future<bool> toggleFavoriteTag(String tag) async {
    final clean = tag.trim();
    final list = List<String>.from(favoriteTags.value);
    // 빈 문자열 청소
    list.removeWhere((e) => e.trim().isEmpty);

    if (clean.isEmpty) {
      await favoriteTags.setValue(list);
      return false;
    }
    final exists = list.contains(clean);
    if (exists) {
      list.remove(clean);
    } else {
      list.insert(0, clean);
    }
    await favoriteTags.setValue(list);
    return !exists;
  }

  static Future<void> removeFavoriteTag(String tag) async {
    final clean = tag.trim();
    final list = List<String>.from(favoriteTags.value);
    list.removeWhere((e) => e.trim().isEmpty || e == tag || (clean.isNotEmpty && e.trim() == clean));
    await favoriteTags.setValue(list);
  }

  static bool isFavoriteTag(String tag) {
    final clean = tag.trim();
    if (clean.isEmpty) return false;
    return favoriteTags.value.any((e) => e.trim() == clean);
  }

  static String get serializedExcludeTags => Settings.excludeTags.value
      .where((e) => e.trim() != '')
      .map((e) => '-$e')
      .join(' ')
      .trim();

  /// 작품이 설정된 기본 제외 태그(Settings.excludeTags)에 해당하는지 판별합니다.
  /// [currentQuery]에 사용자가 직접 입력한 검색어가 있다면 해당 검색어는 예외 처리합니다.
  static bool isExcluded(QueryResult qr, {String currentQuery = ''}) {
    final excludeRules = Settings.excludeTags.value;
    if (excludeRules.isEmpty) return false;

    final queryTokens = currentQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .map((e) => e.replaceAll(' ', '_'))
        .toSet();

    // 작품의 태그 목록 정규화 추출
    final rawTags = qr.result['Tags'] ?? qr.tags();
    final tagTokens = <String>{};
    if (rawTags is List) {
      for (final t in rawTags) {
        final s = t.toString().trim().toLowerCase().replaceAll(' ', '_');
        if (s.isNotEmpty) tagTokens.add(s);
      }
    } else if (rawTags != null) {
      final s = rawTags.toString().trim().toLowerCase();
      if (s.isNotEmpty && s != 'n/a') {
        final split = s.split(RegExp(r'[|,;]'));
        for (final t in split) {
          final clean = t.trim().replaceAll(' ', '_');
          if (clean.isNotEmpty) tagTokens.add(clean);
        }
      }
    }

    Set<String> extractFieldTokens(dynamic raw) {
      if (raw == null) return const <String>{};
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim().toLowerCase().replaceAll(' ', '_'))
            .where((e) => e.isNotEmpty)
            .toSet();
      }
      final s = raw.toString().trim().toLowerCase();
      if (s.isEmpty || s == 'n/a') return const <String>{};
      return s
          .split(RegExp(r'[|,;]'))
          .map((e) => e.trim().replaceAll(' ', '_'))
          .where((e) => e.isNotEmpty)
          .toSet();
    }

    final artistTokens = extractFieldTokens(qr.result['Artists'] ?? qr.artists());
    final groupTokens = extractFieldTokens(qr.result['Groups'] ?? qr.groups());
    final seriesTokens = extractFieldTokens(qr.result['Series'] ?? qr.series());
    final characterTokens = extractFieldTokens(qr.result['Characters'] ?? qr.characters());

    final typeVal = (qr.type() ?? qr.result['Type'])?.toString().trim().toLowerCase().replaceAll(' ', '_') ?? '';
    final langVal = (qr.language() ?? qr.result['Language'])?.toString().trim().toLowerCase().replaceAll(' ', '_') ?? '';
    final uploaderVal = (qr.uploader() ?? qr.result['Uploader'])?.toString().trim().toLowerCase().replaceAll(' ', '_') ?? '';
    final classVal = (qr.classname() ?? qr.result['Class'])?.toString().trim().toLowerCase().replaceAll(' ', '_') ?? '';

    for (var rule in excludeRules) {
      rule = rule.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule.startsWith('-')) rule = rule.substring(1).trim();
      if (rule.isEmpty) continue;

      final normRule = rule.replaceAll(' ', '_');

      // 사용자가 직접 검색창에 해당 태그를 검색어로 입력한 경우 제외 규칙 무시
      if (queryTokens.contains(normRule) || queryTokens.contains(rule)) {
        continue;
      }

      final colonIdx = rule.indexOf(':');
      if (colonIdx != -1) {
        final prefix = rule.substring(0, colonIdx).trim();
        final target = rule.substring(colonIdx + 1).trim();
        final normTarget = target.replaceAll(' ', '_');

        if (queryTokens.contains(normTarget) || queryTokens.contains(target)) {
          continue;
        }

        switch (prefix) {
          case 'female':
          case 'male':
            final full = '$prefix:$normTarget';
            if (tagTokens.contains(full)) return true;
            break;

          case 'tag':
            if (tagTokens.contains(normTarget) ||
                tagTokens.contains('tag:$normTarget') ||
                tagTokens.contains('female:$normTarget') ||
                tagTokens.contains('male:$normTarget')) {
              return true;
            }
            break;

          case 'artist':
            if (artistTokens.any((a) => a == normTarget || a.contains(normTarget))) {
              return true;
            }
            break;

          case 'group':
            if (groupTokens.any((g) => g == normTarget || g.contains(normTarget))) {
              return true;
            }
            break;

          case 'series':
            if (seriesTokens.any((s) => s == normTarget || s.contains(normTarget))) {
              return true;
            }
            break;

          case 'character':
            if (characterTokens.any((c) => c == normTarget || c.contains(normTarget))) {
              return true;
            }
            break;

          case 'type':
            if (typeVal == normTarget) return true;
            break;

          case 'lang':
          case 'language':
            if (langVal == normTarget) return true;
            break;

          case 'uploader':
            if (uploaderVal == normTarget) return true;
            break;

          case 'class':
            if (classVal == normTarget) return true;
            break;

          default:
            if (tagTokens.contains(normRule) || tagTokens.contains(normTarget)) {
              return true;
            }
            break;
        }
      } else {
        // prefix가 없는 일반 단어 (예: 'yaoi', 'furry', 'scat')
        if (tagTokens.contains(normRule) ||
            tagTokens.contains('female:$normRule') ||
            tagTokens.contains('male:$normRule') ||
            tagTokens.contains('tag:$normRule')) {
          return true;
        }
        for (final t in tagTokens) {
          final tColon = t.indexOf(':');
          if (tColon != -1 && t.substring(tColon + 1) == normRule) {
            return true;
          }
        }
      }
    }

    return false;
  }

  // Like this Hitomi.la => e-hentai => exhentai => nhentai
  static List<String> routingRule = <String>[]; // image routing rule
  static List<String> searchRule = <String>[];
  static final searchNetwork = SettingItem<bool>('searchNetwork', false);
  static final fetchWorkInfoNetwork = SettingItem<bool>(
    'fetchWorkInfoNetwork',
    false,
  );
  static final includeTagNetwork = SettingItem<bool>(
    'includeTagNetwork',
    false,
  );
  static final excludeTagNetwork = SettingItem<bool>(
    'excludeTagNetwork',
    true,
  );
  static final searchExpunged = SettingItem<bool>('searchExpunged', true);
  static final groupByFirstPage = SettingItem<bool>('groupByFirstPage', true);
  static final searchCategory = SettingItem<int>('searchCategory', 993);
  static final lastExpungedSyncTime = SettingItem<String>('lastExpungedSyncTime', '');
  static final expungedDbVersion = SettingItem<String>('expungedDbVersion', '');

  // Global? English? Korean?
  static final databaseType = SettingItem<String>('databasetype', () {
    final langcode = Platform.localeName.split('_')[0];
    final acclc = ['ko', 'ja', 'en', 'ru', 'zh'];

    if (!acclc.contains(langcode)) return 'global';

    return langcode;
  }());

  // Reader Option
  static final rightToLeft = SettingItem<bool>('rightToLeft', true);
  static final isHorizontal = SettingItem<bool>('ishorizontal', false);
  static final scrollVertical = SettingItem<bool>('scrollvertical', false);
  static final animation = SettingItem<bool>('animation', false);
  static final padding = SettingItem<bool>('padding', false);
  static final disableOverlayButton = SettingItem<bool>(
    'disableoverlaybutton',
    false,
  );
  static final disableFullScreen = SettingItem<bool>(
    'disablefullscreen',
    false,
  );
  static final enableTimer = SettingItem<bool>('enabletimer', false);
  static final timerTick = SettingItem<double>('timertick', 1.0);
  static final disableTwoPageView = SettingItem<bool>(
    'disableTwoPageView',
    false,
  );
  static final secondPageToSecondPage = SettingItem<bool>(
    'secondPageToSecondPage',
    false,
  );
  static final moveToAppBarToBottom = SettingItem<bool>(
    'movetoappbartobottom',
    Platform.isIOS,
  );
  static final showSlider = SettingItem<bool>('showslider', false);
  static final imageQuality = SettingItem<int>('imagequality', 3);
  static final thumbSize = SettingItem<int>('thumbSize', 1);
  static final enableThumbSlider = SettingItem<bool>(
    'enableThumbSlider',
    false,
  );
  static final showPageNumberIndicator = SettingItem<bool>(
    'showPageNumberIndicator',
    true,
  );
  static final showRecordJumpMessage = SettingItem<bool>(
    'showRecordJumpMessage',
    true,
  );

  static final searchMessageAPI = SettingItem<String>(
    'searchmessageapi',
    'https://koromo.cc/api/search/msg',
  );
  static final useVioletServer = SettingItem<bool>('usevioletserver', false);

  static final useDrawer = SettingItem<bool>('usedrawer', false);

  static final useOptimizeDatabase = SettingItem<bool>(
    'useoptimizedatabase',
    true,
  );

  static final useLowPerf = SettingItem<bool>('uselowperf', true);

  // View Option
  static final showArticleProgress = SettingItem<bool>(
    'showarticleprogress',
    false,
  );

  // Search Option
  static final searchUseFuzzy = SettingItem<bool>('searchusefuzzy', false);
  static final searchTagTranslation = SettingItem<bool>(
    'searchtagtranslation',
    false,
  );
  static final searchUseTranslated = SettingItem<bool>(
    'searchusetranslated',
    false,
  );
  static final searchShowCount = SettingItem<bool>('searchshowcount', true);
  static final searchPure = SettingItem<bool>('searchPure', false);
  static final recordSearchDatabaseOnly = SettingItem<bool>(
    'recordSearchDatabaseOnly',
    false,
  );
  static final lastSearchPosition = SettingItem<int>('lastSearchPosition', 0);
  static final lastSearchArticleId = SettingItem<int>('lastSearchArticleId', 0);
  static final lastSearchArticleTitle = SettingItem<String>(
    'lastSearchArticleTitle',
    '',
  );
  static final lastSearchIsPupil = SettingItem<bool>(
    'lastSearchIsPupil',
    false,
  );

  static late String userAppId;

  static final autobackupBookmark = SettingItem<bool>(
    'autobackupbookmark',
    false,
  );

  // Crop Bookmark
  static final cropBookmarkAlign = SettingItem<int>(
    'cropBookmarkAlign',
    Device.get().isTablet ? 3 : 2,
  );
  static final cropBookmarkShowOverlay = SettingItem<bool>(
    'cropBookmarkShowOverlay',
    true,
  );
  static final cropBookmarkSortDesc = SettingItem<bool>(
    'cropBookmarkSortDesc',
    false,
  );

  // Lab
  static final simpleItemWidgetLoadingIcon = SettingItem<bool>(
    'simpleItemWidgetLoadingIcon',
    true,
  );
  static final showNewViewerWhenArtistArticleListItemTap = SettingItem<bool>(
    'showNewViewerWhenArtistArticleListItemTap',
    true,
  );
  static final enableViewerFunctionBackdropFilter = SettingItem<bool>(
    'enableViewerFunctionBackdropFilter',
    true,
  );
  static final usingPushReplacementOnArticleRead = SettingItem<bool>(
    'usingPushReplacementOnArticleRead',
    true,
  );
  static final downloadEhRawImage = SettingItem<bool>(
    'downloadEhRawImage',
    false,
  );
  static final bookmarkScrollbarPositionToLeft = SettingItem<bool>(
    'bookmarkScrollbarPositionToLeft',
    false,
  );
  static final inViewerMessageSearch = SettingItem<bool>(
    'inViewerMessageSearch',
    false,
  );

  static final useLockScreen = SettingItem<bool>('useLockScreen', false);
  static final useSecureMode = SettingItem<bool>('useSecureMode', false);
  // Version of the last patch note prompt that user dismissed (per-version hide)
  static final lastPatchNoteShownVersion = SettingItem<String>(
    'lastPatchNoteShownVersion',
    '',
  );

  static final useChunkSync = SettingItem<bool>('useChunkSync', true);

  static Future<void> initFirst() async {
    prefs = await SharedPreferences.getInstance();

    await setSecureMode();
  }

  static Future<void> setSecureMode() async {
    if (Platform.isAndroid) {
      if (Settings.useSecureMode.value) {
        await PlatformMiscMethods.instance.setWindowSecure();
      } else {
        await PlatformMiscMethods.instance.setWindowInsecure();
      }
    }
  }

  static Future<void> init() async {
    routingRule = (await _getString(
      'routingrule',
      'Hitomi|EHentai|ExHentai|Hiyobi|NHentai',
    )).split('|');
    searchRule = (await _getString(
      'searchrule',
      'Hitomi|EHentai|ExHentai|NHentai',
    )).split('|');

    if (routingRule.contains('Litomi')) {
      routingRule.remove('Litomi');
      await prefs.setString('routingrule', routingRule.join('|'));
    }
    if (!routingRule.contains('Hiyobi')) {
      routingRule.add('Hiyobi');
      await prefs.setString('routingrule', routingRule.join('|'));
    }

    // searchExpunged_v2: 이로도리/저작권 삭제(Expunged) 작품 검색 기본 활성화 보장
    if (prefs.getBool('searchExpunged_v2') == null) {
      await prefs.setBool('searchExpunged_v2', true);
      await searchExpunged.setValue(true);
    }

    // main에서 셋팅됨
    if (Platform.isAndroid || Platform.isIOS) {
      userAppId = prefs.getString('fa_userid')!;
    } else {
      userAppId = 'null';
    }
  }

  static Future resetIncludeTags() async {
    var language = 'lang:english';
    var langcode = Settings.language.value;
    if (langcode == 'ko') {
      language = 'lang:korean';
    } else if (langcode == 'ja') {
      language = 'lang:japanese';
    } else if (langcode.startsWith('zh')) {
      language = 'lang:chinese';
    }
    await includeTags.setValue('($language)');
  }

  static Future<String> _getString(
    String key, [
    String defaultValue = '',
  ]) async {
    var nn = prefs.getString(key);
    if (nn == null) {
      nn = defaultValue;
      await prefs.setString(key, nn);
    }
    return nn;
  }

  static Future<void> setMajorColor(Color color) async {
    if (majorColor.value == color) return;

    await majorColor.setValue(color);

    Color? accent;
    for (int i = 0; i < Colors.primaries.length - 2; i++) {
      if (color.value == Colors.primaries[i].value) {
        accent = Colors.accents[i];
        break;
      }
    }

    if (accent == null) {
      if (color == Colors.grey) {
        accent = Colors.grey.shade700;
      } else if (color == Colors.brown) {
        accent = Colors.brown.shade700;
      } else if (color == Colors.blueGrey) {
        accent = Colors.blueGrey.shade700;
      } else if (color == Colors.black) {
        accent = Colors.black;
      }
    }

    await majorAccentColor.setValue(accent!);
  }
}

class SettingItem<T> {
  final String key;
  final T defaultValue;
  T? _value;

  SettingItem(this.key, this.defaultValue) {
    load();
  }

  T get value => _value ?? defaultValue;
  Future<void> setValue(T v) async {
    _value = v;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      await saveToPrefs(key, v);
    }
  }

  void load() {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _value = loadFromPrefs<T>(key, defaultValue);
    }
  }

  @override
  String toString() {
    throw UnsupportedError('donot support toString()');
  }
}

class FutureSettingItem<T> {
  final String key;
  final Future<T> Function() computeDefault;
  T? _value;
  bool _initialized = false;

  FutureSettingItem(this.key, this.computeDefault);

  T get value {
    if (!_initialized) {
      throw StateError(
        'FutureSettingItem<$T> not initialized. Call `load()` first.',
      );
    }
    return _value!;
  }

  Future<void> setValue(T v) async {
    _value = v;
    await saveToPrefs(key, v);
  }

  Future<void> load() async {
    _value = loadFromPrefs<T>(key, null);
    if (_value == null) {
      _value = await computeDefault();
      await saveToPrefs<T>(key, _value! as T);
    }
    _initialized = true;
  }

  @override
  String toString() {
    throw UnsupportedError('donot support toString()');
  }
}

T? loadFromPrefs<T>(String key, T? fallback) {
  final prefs = Settings.prefs;
  if (T == bool) return prefs.getBool(key) as T? ?? fallback;
  if (T == int) return prefs.getInt(key) as T? ?? fallback;
  if (T == double) return prefs.getDouble(key) as T? ?? fallback;
  if (T == String) return prefs.getString(key) as T? ?? fallback;
  if (T == Color) {
    final val = prefs.getInt(key);
    return (val != null ? Color(val) : fallback) as T?;
  }
  if (T == List<String>) {
    final val = prefs.getString(key);
    return (val != null ? val.split('|') : fallback) as T?;
  }
  throw Exception('Unsupported type');
}

Future<void> saveToPrefs<T>(String key, T value) async {
  final prefs = Settings.prefs;
  if (value is bool) {
    await prefs.setBool(key, value);
  } else if (value is int) {
    await prefs.setInt(key, value);
  } else if (value is double) {
    await prefs.setDouble(key, value);
  } else if (value is String) {
    await prefs.setString(key, value);
  } else if (value is Color) {
    await prefs.setInt(key, value.value);
  } else if (value is List<String>) {
    await prefs.setString(key, value.join('|'));
  } else {
    throw Exception('Unsupported type');
  }
}

class EnumSettingItem<T extends Enum> {
  final String key;
  final List<T> values;
  final T defaultValue;
  T? _value;

  EnumSettingItem(this.key, this.values, this.defaultValue) {
    load();
  }

  T get value => _value ?? defaultValue;
  Future<void> setValue(T v) async {
    _value = v;
    await Settings.prefs.setInt(key, values.indexOf(v));
  }

  void load() {
    int index = Settings.prefs.getInt(key) ?? values.indexOf(defaultValue);
    _value = values[index];
  }
}

enum SearchResultType { threeGrid, twoGrid, bigLine, detail, ultra }

extension SearchResultTypeExtension on SearchResultType {
  bool get isUltra {
    return this == SearchResultType.ultra;
  }

  bool get isDetailLike {
    switch (this) {
      case SearchResultType.detail:
      case SearchResultType.ultra:
        return true;

      default:
        return false;
    }
  }

  bool get isGridLike {
    switch (this) {
      case SearchResultType.threeGrid:
      case SearchResultType.twoGrid:
        return true;

      default:
        return false;
    }
  }
}
