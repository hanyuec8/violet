// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:synchronized/synchronized.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/database/user/user.dart';
import 'package:violet/log/log.dart';

////////////////////////////////////////////////////////////////////////
///
///         User Record
///
////////////////////////////////////////////////////////////////////////

// // Trivial Log
// class UserLog {
//   Map<String, dynamic> result;
//   UserLog({this.result});

//   int id() => result['Id'];
//   String message() => result['Message'];
//   String datetime() => result['DateTime'];
//   String type() => result['Type'];
// }

// // Specific Log
// class UserActivity {
//   Map<String, dynamic> result;
//   UserActivity({this.result});

//   int id() => result['Id'];
//   String message() => result['Message'];
//   String datetime() => result['DateTime'];

//   // 1: Startup Application
//   // 2: Close Application
//   // 3: Suspend Application
//   // 100: Search
//   // 101: Info View
//   // 120: Viewer Open
//   // 121: Viewer Close
//   int type() => result['Type'];
// }

class ArticleReadLog {
  Map<String, dynamic> result;
  ArticleReadLog({required this.result});

  int id() => result['Id'];
  String articleId() => result['Article'];
  String datetimeStart() => result['DateTimeStart'];
  String? datetimeEnd() => result['DateTimeEnd'];
  int? lastPage() => result['LastPage'];
  // 0: Read on search, 1: Read on bookmark
  int type() => result['Type'];
}

class User {
  static late User _instance;

  static Future<void> load() async {
    try {
      var db = await CommonUserDatabase.getInstance();
      await db.execute('''CREATE TABLE IF NOT EXISTS ArticleReadLog (
            Id integer primary key autoincrement, 
            Article text, 
            DateTimeStart text,
            DateTimeEnd text,
            LastPage integer,
            Type integer);
            ''');
    } catch (e, st) {
      Logger.error(
        '[Record-Instance] E: $e\n'
        '$st',
      );
    }
    _instance = User();
  }

  static Future<void> reset() async {
    await load();
  }

  static Future<User> getInstance() async {
    return _instance;
  }

  List<ArticleReadLog>? cachedReadLog;
  Lock userLogLock = Lock();

  Future<List<ArticleReadLog>> getUserLog() async {
    await userLogLock.synchronized(() async {
      cachedReadLog ??=
          (await (await CommonUserDatabase.getInstance()).query(
                'SELECT * FROM ArticleReadLog ORDER BY Id DESC',
              ))
              // TODO: 왜 Article에 null이 들어가는지 확인 필요
              .where((e) => e['Article'] != null)
              .map((x) => ArticleReadLog(result: x))
              .toList();
    });
    return cachedReadLog!;
  }

  Future<void> insertUserLog(
    int article,
    int type, [
    DateTime? datetime,
  ]) async {
    try {
      datetime ??= DateTime.now();
      final db = await CommonUserDatabase.getInstance();
      final log = ArticleReadLog(
        result: {
          'Article': article.toString(),
          'Type': type,
          'DateTimeStart': datetime.toString(),
        },
      );
      final id = await db.insert('ArticleReadLog', log.result);
      log.result['Id'] = id;
      if (cachedReadLog != null) {
        cachedReadLog!.insert(0, log);
      }
    } catch (e, st) {
      Logger.error('[insertUserLog] E: $e\n$st');
    }
  }

  Future<void> updateUserLog(int article, int lastpage, [DateTime? end]) async {
    try {
      end ??= DateTime.now();
      final db = await CommonUserDatabase.getInstance();
      final artStr = article.toString();

      // cachedReadLog에서 해당 article과 일치하는 최신 로그 탐색
      ArticleReadLog? targetLog;
      if (cachedReadLog != null && cachedReadLog!.isNotEmpty) {
        for (final log in cachedReadLog!) {
          if (log.articleId() == artStr) {
            targetLog = log;
            break;
          }
        }
      }

      if (targetLog != null) {
        targetLog.result['DateTimeEnd'] = end.toString();
        targetLog.result['LastPage'] = lastpage;
        await db.update('ArticleReadLog', targetLog.result, 'Id=?', [targetLog.id()]);
      } else {
        // 캐시에 없거나 캐시 미로드 시 DB에서 직접 해당 article의 최신 로그 조회
        final rows = await db.query(
          "SELECT * FROM ArticleReadLog WHERE Article='$article' ORDER BY Id DESC LIMIT 1",
        );
        if (rows.isNotEmpty) {
          final latestLog = Map<String, dynamic>.from(rows.first);
          latestLog['DateTimeEnd'] = end.toString();
          latestLog['LastPage'] = lastpage;
          await db.update('ArticleReadLog', latestLog, 'Id=?', [latestLog['Id']]);
          if (cachedReadLog != null) {
            cachedReadLog!.insert(0, ArticleReadLog(result: latestLog));
          }
        } else {
          // 혹시 로그가 아예 없었다면 새로 추가
          final newLog = ArticleReadLog(
            result: {
              'Article': artStr,
              'Type': 0,
              'DateTimeStart': end.toString(),
              'DateTimeEnd': end.toString(),
              'LastPage': lastpage,
            },
          );
          final id = await db.insert('ArticleReadLog', newLog.result);
          newLog.result['Id'] = id;
          if (cachedReadLog != null) {
            cachedReadLog!.insert(0, newLog);
          }
        }
      }
    } catch (e, st) {
      Logger.error('[updateUserLog] E: $e\n$st');
    }
  }

  Future<void> clearUserLog() async {
    try {
      final db = await CommonUserDatabase.getInstance();
      await db.execute('DELETE FROM ArticleReadLog');
      cachedReadLog = [];
    } catch (e, st) {
      Logger.error('[clearUserLog] E: $e\n$st');
    }
  }

  static const int defaultProgressExpirationDays = 30;

  /// 작품 진행도(읽은 위치/진행바)의 유효성(표시 여부)을 판정합니다.
  ///
  /// - 읽은 페이지 수가 1 이하인 경우 진행도 없음(false).
  /// - 기본 동작: 모든 열람 작품(북마크 여부, 폴더 위치, 경과 일수와 무관)의 진행도는 기간 제한 없이 영구 보존(true).
  /// - [expirationDays]가 명시적으로 지정된 경우에만 기간 체크를 수행합니다.
  static bool isProgressValid(
    ArticleReadLog log,
    BookmarkArticle? bookmarkArticle, {
    int? expirationDays,
    DateTime? now,
  }) {
    if (log.lastPage() == null || log.lastPage()! <= 1) {
      return false;
    }

    // 명시적으로 만료 일수(expirationDays > 0)가 지정된 경우에만 기간 체크 (기본값은 영구 보존)
    if (expirationDays != null && expirationDays > 0) {
      final currentTime = now ?? DateTime.now();

      // 1. 북마크에 저장된 작품인 경우
      if (bookmarkArticle != null) {
        // 미분류 폴더(GroupId == 1)에 있는 경우: 기간 제한 없이 영구 보존
        if (Bookmark.isDefaultGroupId(bookmarkArticle.group())) {
          return true;
        }

        DateTime? timerBaseTime;
        final moveTime = DateTime.tryParse(bookmarkArticle.datetime());
        final readTime = DateTime.tryParse(log.datetimeStart());

        if (moveTime != null && readTime != null) {
          timerBaseTime = moveTime.isAfter(readTime) ? moveTime : readTime;
        } else {
          timerBaseTime = moveTime ?? readTime;
        }

        if (timerBaseTime == null) return true;

        final diffDays = currentTime.difference(timerBaseTime).inDays;
        return diffDays < expirationDays;
      }

      // 2. 북마크에 없는 일반 작품인 경우: 읽은 시각 기준 타이머
      final readTime = DateTime.tryParse(log.datetimeStart());
      if (readTime == null) return false;

      final diffDays = currentTime.difference(readTime).inDays;
      return diffDays < expirationDays;
    }

    // 기본값: 모든 열람 작품의 진행도를 영구 보존
    return true;
  }
}
