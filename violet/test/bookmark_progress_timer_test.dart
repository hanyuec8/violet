// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter_test/flutter_test.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/database/user/record.dart';

void main() {
  group('Bookmark Progress Timer and Expiration Policy Tests', () {
    final fixedNow = DateTime(2026, 10, 8, 20, 0, 0);

    ArticleReadLog createReadLog({
      required int lastPage,
      required DateTime startTime,
      String articleId = '12345',
    }) {
      return ArticleReadLog(
        result: {
          'Id': 1,
          'Article': articleId,
          'DateTimeStart': startTime.toString(),
          'DateTimeEnd': startTime.add(const Duration(minutes: 10)).toString(),
          'LastPage': lastPage,
          'Type': 0,
        },
      );
    }

    BookmarkArticle createBookmarkArticle({
      required int groupId,
      required DateTime bookmarkTime,
      String articleId = '12345',
    }) {
      return BookmarkArticle(
        result: {
          'Id': 100,
          'Article': articleId,
          'DateTime': bookmarkTime.toString(),
          'GroupId': groupId,
        },
      );
    }

    test('Invalid lastPage (<= 1 or null) is always invalid', () {
      final logPage1 = createReadLog(
        lastPage: 1,
        startTime: fixedNow.subtract(const Duration(days: 1)),
      );
      final logPage0 = createReadLog(
        lastPage: 0,
        startTime: fixedNow.subtract(const Duration(days: 1)),
      );

      final unclassifiedBm = createBookmarkArticle(
        groupId: 1,
        bookmarkTime: fixedNow.subtract(const Duration(days: 1)),
      );

      expect(
        User.isProgressValid(logPage1, unclassifiedBm, now: fixedNow),
        isFalse,
      );
      expect(
        User.isProgressValid(logPage0, unclassifiedBm, now: fixedNow),
        isFalse,
      );
    });

    test('Unclassified folder (GroupId == 1) never expires', () {
      // 10일 전, 35일 전, 365일 전 읽은 작품 모두 미분류 폴더에서는 영구 보존
      final testDurations = [
        const Duration(days: 10),
        const Duration(days: 35),
        const Duration(days: 100),
        const Duration(days: 365),
      ];

      for (final dur in testDurations) {
        final readTime = fixedNow.subtract(dur);
        final log = createReadLog(lastPage: 25, startTime: readTime);
        final bm = createBookmarkArticle(groupId: 1, bookmarkTime: readTime);

        expect(
          User.isProgressValid(log, bm, now: fixedNow),
          isTrue,
          reason: 'Unclassified bookmark read $dur ago should remain valid',
        );
      }
    });

    test('Moved to another folder (GroupId != 1) starts timer from move time', () {
      // 1년 전에 읽었지만 3일 전에 다른 폴더로 옮긴 경우 -> 타이머 시작되어 유효
      final oneYearAgo = fixedNow.subtract(const Duration(days: 365));
      final threeDaysAgo = fixedNow.subtract(const Duration(days: 3));

      final logOld = createReadLog(lastPage: 30, startTime: oneYearAgo);
      final bmRecentlyMoved = createBookmarkArticle(
        groupId: 2,
        bookmarkTime: threeDaysAgo,
      );

      expect(
        User.isProgressValid(logOld, bmRecentlyMoved, now: fixedNow),
        isTrue,
        reason: 'Moved 3 days ago should be valid even if read 1 year ago',
      );

      // 옮긴 지 31일 경과한 경우 -> 만료
      final thirtyOneDaysAgo = fixedNow.subtract(const Duration(days: 31));
      final bmExpiredMove = createBookmarkArticle(
        groupId: 2,
        bookmarkTime: thirtyOneDaysAgo,
      );

      expect(
        User.isProgressValid(logOld, bmExpiredMove, now: fixedNow),
        isFalse,
        reason: 'Moved 31 days ago without recent read should expire',
      );

      // 옮긴 지 29일 경과한 경우 -> 여전히 유효
      final twentyNineDaysAgo = fixedNow.subtract(const Duration(days: 29));
      final bmAlmostExpired = createBookmarkArticle(
        groupId: 2,
        bookmarkTime: twentyNineDaysAgo,
      );

      expect(
        User.isProgressValid(logOld, bmAlmostExpired, now: fixedNow),
        isTrue,
        reason: 'Moved 29 days ago should still be valid within 30 days',
      );
    });

    test('Reading after folder move extends timer based on latest read time', () {
      // 50일 전에 다른 폴더로 옮겼으나, 5일 전에 새로 읽은 경우
      final fiftyDaysAgo = fixedNow.subtract(const Duration(days: 50));
      final fiveDaysAgo = fixedNow.subtract(const Duration(days: 5));

      final logRecent = createReadLog(lastPage: 40, startTime: fiveDaysAgo);
      final bmOldMove = createBookmarkArticle(
        groupId: 3,
        bookmarkTime: fiftyDaysAgo,
      );

      expect(
        User.isProgressValid(logRecent, bmOldMove, now: fixedNow),
        isTrue,
        reason: 'Latest read time within 30 days extends timer',
      );
    });

    test('Non-bookmarked articles follow default 30-day expiration', () {
      // 10일 전 열람: 유효
      final log10d = createReadLog(
        lastPage: 15,
        startTime: fixedNow.subtract(const Duration(days: 10)),
      );
      expect(
        User.isProgressValid(log10d, null, now: fixedNow),
        isTrue,
      );

      // 31일 전 열람: 만료
      final log31d = createReadLog(
        lastPage: 15,
        startTime: fixedNow.subtract(const Duration(days: 31)),
      );
      expect(
        User.isProgressValid(log31d, null, now: fixedNow),
        isFalse,
      );
    });
  });
}
