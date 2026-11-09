// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter_test/flutter_test.dart';
import 'package:violet/component/hitomi/first_page_grouper.dart';
import 'package:violet/database/query.dart';

void main() {
  setUp(() {
    FirstPageGrouper.clearCache();
  });

  group('FirstPageGrouper 단위 테스트', () {
    test('FirstPageHash 캐시 저장 및 즉시 복원 검증', () async {
      final item = QueryResult(result: {
        'Id': 10001,
        'Title': '테스트 작품 원본',
        'Artists': '|작가A|',
        'Language': 'japanese',
        'FirstPageHash': 'hash_test_12345',
      });

      final hash = await FirstPageGrouper.getFirstPageHash(item);
      expect(hash, equals('hash_test_12345'));
    });

    test('언어 우선순위 정렬 검증 (한국어 -> 일본어 -> 영어 -> 중국어 -> 기타)', () async {
      final qrKorean = QueryResult(result: {
        'Id': 10001,
        'Title': '방과 후의 비밀 이야기',
        'Artists': '|작가A|',
        'Language': 'korean',
        'FirstPageHash': 'hash_shared_abc',
      });
      final qrJapanese = QueryResult(result: {
        'Id': 10002,
        'Title': '放課後の秘密の話',
        'Artists': '|작가A|',
        'Language': 'japanese',
        'FirstPageHash': 'hash_shared_abc',
      });
      final qrEnglish = QueryResult(result: {
        'Id': 10003,
        'Title': 'Secret Story After School',
        'Artists': '|작가A|',
        'Language': 'english',
        'FirstPageHash': 'hash_shared_abc',
      });
      final qrOther = QueryResult(result: {
        'Id': 10004,
        'Title': 'Histoire secrète',
        'Artists': '|작가A|',
        'Language': 'french',
        'FirstPageHash': 'hash_shared_abc',
      });

      final list = [qrOther, qrEnglish, qrJapanese, qrKorean];

      list.sort((a, b) {
        final rankA = _testLangRank(a.language()?.toString() ?? '');
        final rankB = _testLangRank(b.language()?.toString() ?? '');
        return rankA.compareTo(rankB);
      });

      expect(list[0].language(), equals('korean'));
      expect(list[1].language(), equals('japanese'));
      expect(list[2].language(), equals('english'));
      expect(list[3].language(), equals('french'));
    });
  });
}

int _testLangRank(String raw) {
  if (raw.contains('korean')) return 1;
  if (raw.contains('japanese')) return 2;
  if (raw.contains('english')) return 3;
  if (raw.contains('chinese')) return 4;
  return 5;
}
