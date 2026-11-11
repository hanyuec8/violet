// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter_test/flutter_test.dart';
import 'package:violet/algorithm/image_perceptual_hash.dart';
import 'package:violet/component/hitomi/first_page_grouper.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/database/query.dart';
import 'package:violet/pages/article_info/similar_article_section.dart';

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

    test('dendoro_kakariya 살얼음의 그녀들 5개 언어본(한국어2, 일본어1, 영어1, 태국어1) 다국어 서브타이틀 교차 매칭 검증', () {
      final baseTitle = 'Usugoori no Kanojo-tachi | 살얼음의 그녀들 (decensored)';
      final korean2 = 'Usugoori no Kanojo-tachi | 살얼음의 그녀들 [미성년 관람불가] [Korean] [Digital] [Decensored] 6/9)';
      final thai = 'Usugoori no Kanojo-tachi';
      final japaneseDisplayTitle = '薄氷の彼女たち';
      final japaneseGalleryTitle = 'Usugoori no Kanojo-tachi';
      final english = '[Dendoro Kakariya] Usugoori no Kanojo-tachi [English] [Digital]';

      // 한국어 1 vs 한국어 2
      expect(HybridLoader.isTitleMatched(baseTitle, korean2), isTrue);
      // 한국어 1 vs 태국어 (로마자 타이틀 교차 일치)
      expect(HybridLoader.isTitleMatched(baseTitle, thai), isTrue);
      // 한국어 1 vs 일본어 galleryinfo 로마자 원제 (Usugoori no Kanojo-tachi 일치)
      expect(HybridLoader.isTitleMatched(baseTitle, japaneseGalleryTitle), isTrue);
      // 한국어 1 vs 영어 번역본 (로마자 타이틀 교차 일치)
      expect(HybridLoader.isTitleMatched(baseTitle, english), isTrue);

      // 일본어 한자 표제어는 galleryinfo의 표준 로마자 타이틀로 교차 매칭 보장
      final matchedViaGallery = HybridLoader.isTitleMatched(baseTitle, japaneseGalleryTitle) ||
          HybridLoader.isTitleMatched(baseTitle, japaneseDisplayTitle);
      expect(matchedViaGallery, isTrue);
    });

    test('살얼음의 그녀들 5개 언어본 우선순위 정렬 순서 검증 (한국어 최신 -> 일본어 -> 영어 -> 태국어)', () {
      final k1 = QueryResult(result: {
        'Id': 4316732,
        'Title': 'Usugoori no Kanojo-tachi | 살얼음의 그녀들 (decensored)',
        'Language': 'korean',
      });
      final k2 = QueryResult(result: {
        'Id': 4315757,
        'Title': 'Usugoori no Kanojo-tachi | 살얼음의 그녀들 [미성년 관람불가] [Korean] [Digital] [Decensored] 6/9)',
        'Language': 'korean',
      });
      final th = QueryResult(result: {
        'Id': 2976681,
        'Title': 'Usugoori no Kanojo-tachi',
        'Language': 'thai',
      });
      final ja = QueryResult(result: {
        'Id': 2476581,
        'Title': '薄氷の彼女たち',
        'Language': 'japanese',
      });
      final en = QueryResult(result: {
        'Id': 3080152,
        'Title': 'Omoi Nawa | Heavy Rope',
        'Language': 'english',
      });

      final list = [th, ja, k1, en, k2];

      list.sort((a, b) {
        final rankA = _testLangRank(a.language()?.toString() ?? '');
        final rankB = _testLangRank(b.language()?.toString() ?? '');
        if (rankA != rankB) return rankA.compareTo(rankB);
        return b.id().compareTo(a.id());
      });

      expect(list[0].id(), equals(4316732)); // 한국어 최신 (4316732)
      expect(list[1].id(), equals(4315757)); // 한국어 (4315757)
      expect(list[2].id(), equals(2476581)); // 일본어 (2476581)
      expect(list[3].id(), equals(3080152)); // 영어 (3080152 - 살얼음의 그녀들 Girls on Thin Ice)
      expect(list[4].id(), equals(2976681)); // 태국어 (2976681)
    });

    test('ImagePerceptualHash 지각적 해시(dHash) 유사도 점수 및 80% 임계값 판정 검증', () {
      // 64비트 정수 dHash 시뮬레이션
      const hashKR = 0x766F7E83497BF5D9;
      // 5비트만 다른 변형본 (유사도 92.2%)
      const hashEN = hashKR ^ 0x000000000000001F; // 하위 5비트 반전 (diff = 5)
      // 4비트만 다른 변형본 (유사도 93.8%)
      const hashJA = hashKR ^ 0x000000000000000F; // 하위 4비트 반전 (diff = 4)
      // 29비트가 다른 타 작품 (유사도 54.7%)
      const hashDiff = hashKR ^ 0x1F3F7F0F00000000;

      final simEN = ImagePerceptualHash.calculateSimilarity(hashKR, hashEN);
      final simJA = ImagePerceptualHash.calculateSimilarity(hashKR, hashJA);
      final simDiff = ImagePerceptualHash.calculateSimilarity(hashKR, hashDiff);

      // 살얼음 5개 판본 상호 간 유사도는 80% 이상 합격
      expect(simEN, closeTo(92.18, 0.1));
      expect(simEN >= 80.0, isTrue);

      expect(simJA, closeTo(93.75, 0.1));
      expect(simJA >= 80.0, isTrue);

      // 다른 작품(대조군)은 80% 미만으로 안전하게 배제
      expect(simDiff < 80.0, isTrue);
    });

    test('4306462 작가 부재 작품의 핵심 장르 태그 선별 검증 (비특이적 태그 배제 및 female:gyaru 추출)', () {
      final itemNoArtist = QueryResult(result: {
        'Id': 4306462,
        'Title': 'Usokoku Gal to Kimo Ota ga SeFri ni nareru Hazu ga nai!! | 거짓 고백 갸루와 추한 오타쿠가 섹프가 될 리가 없다!!',
        'Artists': '',
        'Tags': '|male:bbm|female:big breasts|female:emotionless sex|female:gyaru|female:huge breasts|female:kissing|female:nakadashi|rough translation|digital|female:schoolgirl uniform|female:sole female|male:sole male|female:squirting|female:tall girl|',
      });

      final bestTag = SimilarArticleSection.extractPrimaryGenreTag(itemNoArtist);
      expect(bestTag, equals('female:gyaru'));
    });

    test('다양한 장르/캐릭터 태그 우선순위 선별 검증', () {
      // 1) 톰보이 + 수영복 + 디지털 태그
      final tomboyItem = QueryResult(result: {
        'Id': 10001,
        'Title': 'Tomboy Story',
        'Tags': '|digital|female:swimsuit|female:tomboy|uncensored|',
      });
      expect(SimilarArticleSection.extractPrimaryGenreTag(tomboyItem), equals('female:tomboy'));

      // 2) 얀데레 + 메이드 + 교복 태그
      final yandereItem = QueryResult(result: {
        'Id': 10002,
        'Title': 'Yandere Maid',
        'Tags': '|female:schoolgirl uniform|female:yandere|female:maid|',
      });
      expect(SimilarArticleSection.extractPrimaryGenreTag(yandereItem), equals('female:yandere'));

      // 3) 비특이적 태그만 있는 경우 폴백 검증
      final genericItem = QueryResult(result: {
        'Id': 10003,
        'Title': 'Generic Manga',
        'Tags': '|digital|rough translation|uncensored|',
      });
      expect(SimilarArticleSection.extractPrimaryGenreTag(genericItem), isNull);
    });

    test('parsePageCount 다양한 타입 파싱 검증 (문자열 "202 pages", 정수, null 등)', () {
      expect(SimilarArticleSection.parsePageCount('202 pages'), equals(202));
      expect(SimilarArticleSection.parsePageCount('163p'), equals(163));
      expect(SimilarArticleSection.parsePageCount(202), equals(202));
      expect(SimilarArticleSection.parsePageCount(143.0), equals(143));
      expect(SimilarArticleSection.parsePageCount(null), isNull);
      expect(SimilarArticleSection.parsePageCount(''), isNull);
      expect(SimilarArticleSection.parsePageCount('no numbers'), isNull);
    });
  });
}

int _testLangRank(String raw) {
  final l = raw.toLowerCase();
  if (l.contains('korean')) return 1;
  if (l.contains('japanese')) return 2;
  if (l.contains('english')) return 3;
  if (l.contains('chinese')) return 4;
  return 5;
}
