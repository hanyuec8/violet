import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:violet/component/hitomi/tag_catalog.dart';
import 'package:violet/component/hitomi/tag_translate.dart';
import 'package:violet/component/index.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.current.path;
      },
    );
    await TagTranslate.init();
    await HentaiIndex.init();
  });

  test('HitomiTagCatalog loads K artists and finds kamushi', () async {
    final artists = await HitomiTagCatalog.searchArtists('kamu');
    expect(artists.isNotEmpty, true);
    expect(artists.contains('kamushi'), true);

    // 접두사 일치 작가가 최상단에 있는지 검증
    expect(artists.first.toLowerCase().startsWith('kamu'), true);
  });

  test('HentaiIndex autocomplete ranks kamushi at top for kamu', () async {
    final results = await HentaiIndex.queryAutoComplete('kamu');
    expect(results.isNotEmpty, true);

    final kamushiIdx = results.indexWhere((e) => e.$1.name == 'kamushi' && e.$1.group == 'artist');
    expect(kamushiIdx != -1, true, reason: 'kamushi must be present in autocomplete results');

    print('kamushi rank in autocomplete: $kamushiIdx out of ${results.length}');
    for (int i = 0; i < results.length && i < 10; i++) {
      final (tag, count) = results[i];
      print('[$i] ${tag.group}:${tag.name} (${tag.translated}) count: $count');
    }

    // kamushi는 접두사 일치이므로 상위 10위 이내에 위치해야 함
    expect(kamushiIdx < 10, true);

    // 중간 일치 작가(예: nakamura regura 등)보다 kamushi가 상위인지 검증
    final nakamuraIdx = results.indexWhere((e) => e.$1.name == 'nakamura regura');
    if (nakamuraIdx != -1) {
      expect(kamushiIdx < nakamuraIdx, true, reason: 'kamushi must rank above nakamura regura');
    }
  });

  test('HentaiIndex autocomplete for artist:kamu finds kamushi', () async {
    final results = await HentaiIndex.queryAutoComplete('artist:kamu');
    expect(results.isNotEmpty, true);

    final kamushiIdx = results.indexWhere((e) => e.$1.name == 'kamushi');
    expect(kamushiIdx != -1, true);
    print('artist:kamu rank for kamushi: $kamushiIdx');
    expect(kamushiIdx < 10, true);
  });

  test('HitomiTagCatalog finds kawasaki tadataka when searching tadataka', () async {
    // k로 시작하는 작가 목록을 직접 또는 캐시로부터 스캔하여 tadataka 검색 시 검출되는지 검증
    await HitomiTagCatalog.loadArtists('k');
    final artists = await HitomiTagCatalog.searchArtists('tadataka');
    expect(artists.isNotEmpty, true);
    expect(artists.contains('kawasaki tadataka'), true, reason: 'kawasaki tadataka must be found via subword tadataka');
  });

  test('HentaiIndex autocomplete for tadataka finds and ranks kawasaki tadataka near top', () async {
    await HitomiTagCatalog.loadArtists('k');
    final results = await HentaiIndex.queryAutoComplete('tadataka');
    expect(results.isNotEmpty, true);

    final tadatakaIdx = results.indexWhere((e) => e.$1.name == 'kawasaki tadataka' && e.$1.group == 'artist');
    expect(tadatakaIdx != -1, true, reason: 'kawasaki tadataka must be present in autocomplete for tadataka');

    print('kawasaki tadataka rank in autocomplete for tadataka: $tadatakaIdx out of ${results.length}');
    for (int i = 0; i < results.length && i < 10; i++) {
      final (tag, count) = results[i];
      print('[$i] ${tag.group}:${tag.name} (${tag.translated}) count: $count');
    }

    // kawasaki tadataka는 단어 단위 접두사 일치이므로 최상위(10위 이내)에 랭크되어야 함
    expect(tadatakaIdx < 10, true);
  });

  test('HentaiIndex autocomplete for artist:tadataka finds kawasaki tadataka', () async {
    await HitomiTagCatalog.loadArtists('k');
    final results = await HentaiIndex.queryAutoComplete('artist:tadataka');
    expect(results.isNotEmpty, true);

    final tadatakaIdx = results.indexWhere((e) => e.$1.name == 'kawasaki tadataka');
    expect(tadatakaIdx != -1, true, reason: 'kawasaki tadataka must be present in artist:tadataka autocomplete');
    print('artist:tadataka rank for kawasaki tadataka: $tadatakaIdx');
    expect(tadatakaIdx < 10, true);
  });

  test('Autocomplete without index.json (pure catalog mode) finds kawasaki tadataka for tadataka', () async {
    // tagCount가 없는 순수 카탈로그 모드 시뮬레이션
    HentaiIndex.tagCount = null;
    await HitomiTagCatalog.loadArtists('k');

    final results = await HentaiIndex.queryAutoComplete('tadataka');
    expect(results.isNotEmpty, true);

    final tadatakaIdx = results.indexWhere((e) => e.$1.name == 'kawasaki tadataka' && e.$1.group == 'artist');
    expect(tadatakaIdx != -1, true, reason: 'kawasaki tadataka must be found even without index.json');
    print('pure catalog mode rank for kawasaki tadataka: $tadatakaIdx');
    expect(tadatakaIdx < 5, true);
  });
}
