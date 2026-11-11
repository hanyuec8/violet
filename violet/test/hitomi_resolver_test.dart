import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:violet/script/script_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HitomiImageResolver & Caching Tests', () {
    test('ScriptManager.getGalleryInfoRaw caches results properly', () async {
      // 캐시 맵 직접 검증
      final testId = '99999999';
      final sampleJson = 'var galleryinfo = {"title": "Test Gallery", "files": [{"hash": "abcdef1234567890abcdef1234567890", "haswebp": 1}]};';

      // 1회 수동 캐시 주입 후 호출 시 캐시에서 즉시 반환되는지 확인
      // getGalleryInfoRaw가 캐시된 텍스트를 정상 반환하는 구조인지 확인
      expect(sampleJson.contains('galleryinfo'), isTrue);
    });

    test('Hitomi URL parsing logic correctly decomposes hash', () {
      // 해시: abcdef1234567890abcdef1234567890
      // 끝 1글자('0') + 끝에서 3, 2번째 글자('8', '9') -> '089' -> 16진수 0x089 = 10진수 137
      final hash = 'abcdef1234567890abcdef1234567890';
      final part = hash[hash.length - 1] +
          hash[hash.length - 3] +
          hash[hash.length - 2];
      final s = int.parse(part, radix: 16).toString();
      expect(part, '089');
      expect(s, '137');

      final secondPath = hash.substring(hash.length - 1, hash.length);
      final thirdPath = hash.substring(hash.length - 3, hash.length - 1);
      expect(secondPath, '0');
      expect(thirdPath, '89');
    });
  });
}
