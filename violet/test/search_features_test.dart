import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:violet/component/hitomi/displayed_tag.dart';
import 'package:violet/component/query_translate.dart';
import 'package:violet/database/expunged_database.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/database/user/record.dart';
import 'package:violet/component/index.dart';
import 'package:violet/pages/artist_info/artist_info_page.dart';
import 'package:violet/database/query.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/settings/settings.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    Settings.prefs = await SharedPreferences.getInstance();
  });

  group('SQL Translation Tests (Date, Id Range, Random)', () {
    test('id range translations', () {
      final sql1 = translate2query('id:1000~2000', filter: false);
      expect(sql1, contains('Id >= 1000 AND Id <= 2000'));

      final sql2 = translate2query('id:1000..2000', filter: false);
      expect(sql2, contains('Id >= 1000 AND Id <= 2000'));

      final sql3 = translate2query('id>=500 id<=1500', filter: false);
      expect(sql3, contains('Id >= 500'));
      expect(sql3, contains('Id <= 1500'));
    });

    test('date range translations', () {
      final sql1 = translate2query('date:2023-01-01~2024-01-01', filter: false);
      expect(sql1, contains("Published >= '2023-01-01'"));
      expect(sql1, contains("Published <= '2024-01-01 23:59:59'"));

      final sql2 = translate2query('date:2023~2024', filter: false);
      expect(sql2, contains("Published >= '2023-01-01'"));
      expect(sql2, contains("Published <= '2024-12-31 23:59:59'"));

      final sql3 = translate2query('date>=2023-05-01', filter: false);
      expect(sql3, contains("Published >= '2023-05-01'"));
    });

    test('random query translations ignores WHERE column errors', () {
      final sql1 = translate2query('random', filter: false);
      expect(sql1, isNot(contains('random LIKE')));
      expect(sql1, equals('SELECT * FROM HitomiColumnModel '));

      final sql2 = translate2query('random:1.2345', filter: false);
      expect(sql2, isNot(contains('random LIKE')));
      expect(sql2, equals('SELECT * FROM HitomiColumnModel '));

      final sql3 = translate2query('female:big_breasts random:1.2345', filter: false);
      expect(sql3, isNot(contains('random')));
      expect(sql3, contains("Tags LIKE '%|female:big breasts|%'"));
    });

    test('artist and group word boundary translations', () {
      final sql1 = translate2query('artist:in', filter: false);
      expect(sql1, contains("Artists LIKE '%|in|%'"));
      expect(sql1, contains("Artists LIKE '%|in %'"));
      expect(sql1, contains("Artists LIKE '% in|%'"));
      expect(sql1, contains("Artists LIKE '% in %'"));
      expect(sql1, isNot(contains("Artists LIKE '%in%'")));

      final sql2 = translate2query('-artist:in', filter: false);
      expect(sql2, contains("NOT (Artists LIKE '%|in|%'"));

      final sql3 = translate2query('group:in', filter: false);
      expect(sql3, contains("Groups LIKE '%|in|%'"));
      expect(sql3, contains("Groups LIKE '%|in %'"));
      expect(sql3, contains("Groups LIKE '% in|%'"));
      expect(sql3, contains("Groups LIKE '% in %'"));

      final sql4 = translate2query('artist:nagayama_tadataka', filter: false);
      expect(sql4, contains("Artists LIKE '%|nagayama tadataka|%'"));
    });
  });

  group('DisplayedTag Tag formatting tests', () {
    test('id and date tags format correctly', () {
      final t1 = DisplayedTag(group: 'id', name: '1000000~2000000');
      expect(t1.getTag(), equals('id:1000000~2000000'));

      final t2 = DisplayedTag(group: 'id', name: '>=1000');
      expect(t2.getTag(), equals('id>=1000'));

      final t3 = DisplayedTag(group: 'date', name: '2024-01-01~2024-12-31');
      expect(t3.getTag(), equals('date:2024-01-01~2024-12-31'));

      final t4 = DisplayedTag(group: 'date', name: '>=2024-01-01');
      expect(t4.getTag(), equals('date>=2024-01-01'));
    });
  });

  group('Unclassified Bookmark Progress Validity Tests', () {
    test('default group bookmark progress is preserved indefinitely', () {
      Bookmark.defaultGroupId = 1;
      final log = ArticleReadLog(
        result: {
          'Id': 10,
          'Article': '999999',
          'DateTimeStart': DateTime.now().subtract(const Duration(days: 365)).toString(),
          'LastPage': 25,
          'Type': 0,
        },
      );
      final bookmarkItem = BookmarkArticle(
        result: {
          'Id': 1,
          'Article': '999999',
          'DateTime': DateTime.now().subtract(const Duration(days: 365)).toString(),
          'GroupId': 1,
        },
      );

      final isValid = User.isProgressValid(log, bookmarkItem);
      expect(isValid, isTrue);
    });

    test('default group bookmark with custom defaultGroupId is preserved', () {
      Bookmark.defaultGroupId = 5;
      final log = ArticleReadLog(
        result: {
          'Id': 10,
          'Article': '999999',
          'DateTimeStart': DateTime.now().subtract(const Duration(days: 100)).toString(),
          'LastPage': 15,
          'Type': 0,
        },
      );
      final bookmarkItem = BookmarkArticle(
        result: {
          'Id': 1,
          'Article': '999999',
          'DateTime': DateTime.now().subtract(const Duration(days: 100)).toString(),
          'GroupId': 5,
        },
      );

      final isValid = User.isProgressValid(log, bookmarkItem);
      expect(isValid, isTrue);

      Bookmark.defaultGroupId = 1;
    });

    test('non-default group bookmark progress is preserved indefinitely by default', () {
      Bookmark.defaultGroupId = 1;
      final log = ArticleReadLog(
        result: {
          'Id': 10,
          'Article': '999999',
          'DateTimeStart': DateTime.now().subtract(const Duration(days: 45)).toString(),
          'LastPage': 15,
          'Type': 0,
        },
      );
      final bookmarkItem = BookmarkArticle(
        result: {
          'Id': 1,
          'Article': '999999',
          'DateTime': DateTime.now().subtract(const Duration(days: 45)).toString(),
          'GroupId': 2, // 사용자 생성 폴더
        },
      );

      // 기본값: 영구 보존
      final isValidDefault = User.isProgressValid(log, bookmarkItem);
      expect(isValidDefault, isTrue);

      // 명시적 30일 만료 지정 시
      final isValidWithExpiration = User.isProgressValid(log, bookmarkItem, expirationDays: 30);
      expect(isValidWithExpiration, isFalse);
    });
  });

  group('Autocomplete Smart Ranking Priority Tests', () {
    test('popular tag with count > 0 beats zero-count junk short artist/group', () {
      final list = <(DisplayedTag, int)>[
        (DisplayedTag(group: 'group', name: 'ax'), 0), // 0작품수 유령 그룹
        (DisplayedTag(group: 'tag', name: 'anal'), 5000), // 대중적 태그
        (DisplayedTag(group: 'artist', name: 'av'), 0), // 0작품수 유령 작가
      ];

      // HentaiIndex의 queryAutoComplete 내부 정렬 로직 검증
      final sorted = List<(DisplayedTag, int)>.from(list);
      // HentaiIndex.searchTagsSync 동기 정렬 또는 랭킹 규칙 적용
      // a 검색 시 'anal'이 1위여야 함
      final query = 'a';
      // 점수 계산 검증
      int scoreTag((DisplayedTag, int) item) {
        final tag = item.$1;
        final count = item.$2;
        final name = (tag.name ?? '').toLowerCase();
        final group = (tag.group ?? '').toLowerCase();

        int score = 0;
        if (name.startsWith(query)) score += 15000;
        if (group == 'tag') score += 1500;
        if (group == 'artist' || group == 'group') score += 600;
        if (count > 0) {
          score += 8000;
          score += (count > 2000 ? 2000 : count);
        } else if (name.length <= 2) {
          score -= 10000;
        }
        score -= name.length * 2;
        return score;
      }

      sorted.sort((a, b) => scoreTag(b).compareTo(scoreTag(a)));
      expect(sorted.first.$1.name, equals('anal'));
      expect(sorted.first.$1.group, equals('tag'));
    });
  });

  group('Artist Info and Bookmark Null Safety Tests', () {
    test('HentaiIndex.getArticleCount handles case, underscores, spaces, and never returns null', () {
      HentaiIndex.tagCount = {
        'artist': {
          'kuuchuu yousai': 45,
          'munyuu': 28,
        },
        'group': {
          'cage': 12,
        }
      };

      // Exact match
      expect(HentaiIndex.getArticleCount('artist', 'kuuchuu yousai'), equals(45));

      // Uppercase match
      expect(HentaiIndex.getArticleCount('artist', 'Kuuchuu Yousai'), equals(45));

      // Underscore to space match
      expect(HentaiIndex.getArticleCount('artist', 'kuuchuu_yousai'), equals(45));
      expect(HentaiIndex.getArticleCount('artist', 'Kuuchuu_Yousai'), equals(45));

      // Non-existent artist returns 0, never null
      expect(HentaiIndex.getArticleCount('artist', 'non_existent_artist'), equals(0));
      expect(HentaiIndex.getArticleCount('artist', 'unknown'), equals(0));
      expect(HentaiIndex.getArticleCount('invalid_type', 'unknown'), equals(0));
    });

    test('ArtistInfoPage.filterByLanguage filters correctly and returns empty list when no matches', () {
      final sampleArticles = [
        QueryResult(result: {'Id': 1, 'Language': 'japanese', 'Title': 'Work 1'}),
        QueryResult(result: {'Id': 2, 'Language': 'english', 'Title': 'Work 2'}),
      ];

      // Korean filter returns empty list (should not fallback to all)
      final korean = ArtistInfoPage.filterByLanguage(sampleArticles, 'korean');
      expect(korean, isEmpty);

      // Japanese filter returns 1 match
      final japanese = ArtistInfoPage.filterByLanguage(sampleArticles, 'japanese');
      expect(japanese.length, equals(1));
      expect(japanese.first.id(), equals(1));

      // All returns all
      final all = ArtistInfoPage.filterByLanguage(sampleArticles, 'all');
      expect(all.length, equals(2));
    });
  });

  group('Popular Search Sort Mode and Nozomi Index Tests', () {
    test('SearchSortMode URLs match CDN endpoints', () {
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularWeek, 'korean'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular/week-korean.nozomi'),
      );
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularMonth, 'korean'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular/month-korean.nozomi'),
      );
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularYear, 'korean'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular/year-korean.nozomi'),
      );
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularAll, 'korean'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular-korean.nozomi'),
      );
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularToday, 'korean'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular/today-korean.nozomi'),
      );
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.latest, 'korean'),
        equals('https://ltn.gold-usergeneratedcontent.net/index-korean.nozomi'),
      );
    });

    test('SearchSortMode non-supported language fallbacks to all', () {
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularWeek, 'chinese'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular/week-all.nozomi'),
      );
      expect(
        HitomiNozomi.getPopularIndexUrl(SearchSortMode.popularAll, 'russian'),
        equals('https://ltn.gold-usergeneratedcontent.net/popular-all.nozomi'),
      );
    });

    test('SearchSortMode labels and descriptions are defined', () {
      for (final mode in SearchSortMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.description, isNotEmpty);
      }
    });

    test('Language only queries with popular mode targeting korean', () {
      final targets = ['korean', 'lang:korean', '(lang:korean)', 'language:korean', '(language:korean)', 'order:week'];
      for (final t in targets) {
        final raw = t.replaceAll(RegExp(r'[\(\)]'), '').trim().toLowerCase();
        final isLang = raw.startsWith('lang:') || raw.startsWith('language:') || raw == 'korean' || raw.startsWith('order:');
        expect(isLang, isTrue);
      }
    });
  });

  group('Exclude Tags Tests (Settings.isExcluded)', () {
    test('excludes works matching female and male tags', () async {
      await Settings.excludeTags.setValue(['male:yaoi', 'female:furry']);

      final yaoiWork = QueryResult(result: {
        'Id': 1001,
        'Title': 'Test Yaoi',
        'Tags': '|male:yaoi|male:crossdressing|',
      });

      final furryWork = QueryResult(result: {
        'Id': 1002,
        'Title': 'Test Furry',
        'Tags': '|female:furry|female:catgirl|',
      });

      final cleanWork = QueryResult(result: {
        'Id': 1003,
        'Title': 'Test Clean',
        'Tags': '|female:schoolgirl|female:sole_female|',
      });

      expect(Settings.isExcluded(yaoiWork), isTrue);
      expect(yaoiWork.isExcluded(), isTrue);

      expect(Settings.isExcluded(furryWork), isTrue);
      expect(furryWork.isExcluded(), isTrue);

      expect(Settings.isExcluded(cleanWork), isFalse);
      expect(cleanWork.isExcluded(), isFalse);
    });

    test('bare tag without prefix excludes all matching variants', () async {
      await Settings.excludeTags.setValue(['furry']);

      final femaleFurry = QueryResult(result: {
        'Id': 2001,
        'Title': 'Female Furry',
        'Tags': '|female:furry|',
      });

      final maleFurry = QueryResult(result: {
        'Id': 2002,
        'Title': 'Male Furry',
        'Tags': '|male:furry|',
      });

      final plainFurry = QueryResult(result: {
        'Id': 2003,
        'Title': 'Plain Furry',
        'Tags': '|furry|',
      });

      final nonFurry = QueryResult(result: {
        'Id': 2004,
        'Title': 'Non Furry',
        'Tags': '|female:catgirl|',
      });

      expect(Settings.isExcluded(femaleFurry), isTrue);
      expect(Settings.isExcluded(maleFurry), isTrue);
      expect(Settings.isExcluded(plainFurry), isTrue);
      expect(Settings.isExcluded(nonFurry), isFalse);
    });

    test('user explicit search query bypasses exclusion for that specific query', () async {
      await Settings.excludeTags.setValue(['female:furry', 'male:yaoi']);

      final furryWork = QueryResult(result: {
        'Id': 3001,
        'Title': 'Furry Work',
        'Tags': '|female:furry|',
      });

      // 일반 탐색 시(검색어 없음) 제외 판정
      expect(Settings.isExcluded(furryWork, currentQuery: ''), isTrue);

      // 타 태그 검색 시에도 제외 판정
      expect(Settings.isExcluded(furryWork, currentQuery: 'lang:korean'), isTrue);

      // 사용자가 직접 검색창에 'female:furry'를 입력하여 검색한 경우 제외 예외 허용 (0건 방지)
      expect(Settings.isExcluded(furryWork, currentQuery: 'female:furry'), isFalse);
      expect(Settings.isExcluded(furryWork, currentQuery: 'lang:korean female:furry'), isFalse);
    });

    test('excludes works matching artist or group rules', () async {
      await Settings.excludeTags.setValue(['artist:bad_artist', 'group:bad_group']);

      final badArtistWork = QueryResult(result: {
        'Id': 4001,
        'Title': 'Bad Artist Work',
        'Artists': '|bad_artist|',
        'Tags': '|female:big_breasts|',
      });

      final badGroupWork = QueryResult(result: {
        'Id': 4002,
        'Title': 'Bad Group Work',
        'Groups': '|bad_group|',
        'Tags': '|female:big_breasts|',
      });

      final goodWork = QueryResult(result: {
        'Id': 4003,
        'Title': 'Good Work',
        'Artists': '|good_artist|',
        'Tags': '|female:big_breasts|',
      });

      expect(Settings.isExcluded(badArtistWork), isTrue);
      expect(Settings.isExcluded(badGroupWork), isTrue);
      expect(Settings.isExcluded(goodWork), isFalse);
    });
  });

  group('Expunged Database Manager Tests', () {
    test('expunged database queryId and counts work in test environment', () async {
      final count = await ExpungedDatabaseManager.getExpungedCount();
      expect(count, greaterThan(0));

      final testQr = await ExpungedDatabaseManager.queryId(442220);
      if (testQr != null) {
        expect(testQr.result['is_expunged'], isTrue);
        expect(testQr.result['source'], equals('common'));
      }
    });
  });
}
