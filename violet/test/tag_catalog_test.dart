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
}
