// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:synchronized/synchronized.dart';
import 'package:violet/database/query.dart';
import 'package:violet/log/log.dart';
import 'package:violet/network/wrapper.dart' as http;
import 'package:violet/pages/search/search_page_controller.dart';
import 'package:violet/settings/settings.dart';

class ExpungedDatabaseManager {
  static const String defaultOnlineDbUrl =
      'https://github.com/hanyuec8/violet-lite/releases/download/database/expunged.db';
  static const String fallbackOnlineDbUrl =
      'https://raw.githubusercontent.com/hanyuec8/violet-lite/database/assets/database/expunged.db';

  static Database? _db;
  static final Lock _lock = Lock();

  static bool get isOpen => _db != null && _db!.isOpen;

  static Future<String> getDbPath() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      var p = join(Directory.current.path, 'assets/database/expunged.db');
      if (!File(p).existsSync()) {
        p = join(Directory.current.path, '../expunged.db');
      }
      return p;
    }
    final dir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(join(dir.path, 'data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    return join(dataDir.path, 'expunged.db');
  }

  static bool _isValidSqliteFile(Uint8List bytes) {
    if (bytes.length < 16) return false;
    const sqliteHeader = [
      0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
      0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
    ];
    for (var i = 0; i < 16; i++) {
      if (bytes[i] != sqliteHeader[i]) return false;
    }
    return true;
  }

  static bool _silentSyncTriggered = false;

  static void _triggerSilentSync() {
    if (_silentSyncTriggered || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _silentSyncTriggered = true;
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        await syncOnlineDatabase(silent: true);
      } catch (_) {}
    });
  }

  static Future<Database?> getInstance() async {
    if (!Settings.searchExpunged.value) return null;

    if (_db != null && _db!.isOpen) {
      _triggerSilentSync();
      return _db;
    }

    await _lock.synchronized(() async {
      if (_db != null && _db!.isOpen) return;

      try {
        if (Platform.environment.containsKey('FLUTTER_TEST')) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
        }

        final dbPath = await getDbPath();
        final dbFile = File(dbPath);

        if (!Platform.environment.containsKey('FLUTTER_TEST')) {
          try {
            final assetData = await rootBundle.load('assets/database/expunged.db');
            final assetBytes = assetData.lengthInBytes;
            if (!await dbFile.exists() ||
                (await dbFile.length() != assetBytes &&
                    Settings.expungedDbVersion.value.isEmpty)) {
              Logger.info('[ExpungedDB] Copying expunged.db from assets ($assetBytes bytes)...');
              final bytes = assetData.buffer.asUint8List(
                assetData.offsetInBytes,
                assetData.lengthInBytes,
              );
              await dbFile.writeAsBytes(bytes, flush: true);
              Logger.info('[ExpungedDB] Seed copy completed');
            }
          } catch (e) {
            Logger.warning('[ExpungedDB] Asset check error: $e');
          }
        }

        if (await dbFile.exists() && await dbFile.length() > 0) {
          _db = await openReadOnlyDatabase(dbPath);
          if (Settings.lastExpungedSyncTime.value.isEmpty) {
            await Settings.lastExpungedSyncTime.setValue('2026-11-01');
          }
          Logger.info('[ExpungedDB] Opened successfully at $dbPath');
        }
      } catch (e, st) {
        Logger.error('[ExpungedDB] Init error: $e\n$st');
      }
    });

    _triggerSilentSync();
    return _db;
  }

  /// 온라인 서버(GitHub Releases / Raw CDN)와 통신하여 최신 이로도리 삭제작 DB를 동기화합니다.
  /// [force]가 true이면 버전 비교 없이 즉시 최신본을 내려받습니다.
  /// [silent]가 true이면 사용자 개입 없이 백그라운드에서 조용히 수행합니다.
  static Future<bool> syncOnlineDatabase({
    bool force = false,
    bool silent = false,
  }) async {
    final dbPath = await getDbPath();
    final dataDir = Directory(dirname(dbPath));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    final urls = [defaultOnlineDbUrl, fallbackOnlineDbUrl];

    for (final url in urls) {
      try {
        Logger.info('[ExpungedDB] Checking online update from $url ...');

        String versionTag = '';
        try {
          final headRes = await http.head(url).timeout(
            const Duration(seconds: 7),
          );

          if (headRes.statusCode == 200 || headRes.statusCode == 302) {
            final etag = headRes.headers['etag'] ?? '';
            final lastMod = headRes.headers['last-modified'] ?? '';
            final length = headRes.headers['content-length'] ?? '';
            versionTag = '${etag}_${lastMod}_$length'.trim();

            if (!force &&
                versionTag.isNotEmpty &&
                versionTag == Settings.expungedDbVersion.value &&
                File(dbPath).existsSync() &&
                File(dbPath).lengthSync() > 100000) {
              Logger.info('[ExpungedDB] Already up-to-date ($versionTag).');
              return false;
            }
          }
        } catch (_) {}

        Logger.info('[ExpungedDB] Downloading online expunged DB from $url ...');
        final tmpPath = join(dataDir.path, 'expunged.db.tmp');
        final tmpFile = File(tmpPath);
        if (await tmpFile.exists()) await tmpFile.delete();

        final response = await http.get(url).timeout(
          const Duration(seconds: 45),
        );

        if (response.statusCode != 200) {
          throw Exception('HTTP status ${response.statusCode}');
        }

        final bytes = response.bodyBytes;
        if (bytes.length < 100000 || !_isValidSqliteFile(bytes)) {
          throw Exception('Invalid SQLite DB file (size: ${bytes.length})');
        }

        await tmpFile.writeAsBytes(bytes, flush: true);

        // 원자적 파일 교체 및 SQLite 커넥션 무중단 핫 리로드
        await _lock.synchronized(() async {
          if (_db != null && _db!.isOpen) {
            await _db!.close();
            _db = null;
          }
          final targetFile = File(dbPath);
          if (await targetFile.exists()) {
            await targetFile.delete();
          }
          await tmpFile.rename(dbPath);
          _db = await openReadOnlyDatabase(dbPath);
        });

        if (versionTag.isNotEmpty) {
          await Settings.expungedDbVersion.setValue(versionTag);
        }
        await Settings.lastExpungedSyncTime.setValue(DateTime.now().toIso8601String());

        Logger.info('[ExpungedDB] Successfully updated online DB (${bytes.length} bytes)');
        if (silent) {
          SearchPageController.current?.applyExcludedTagsFilter();
        }
        return true;
      } catch (e, st) {
        Logger.warning('[ExpungedDB] Failed downloading from $url: $e\n$st');
        continue;
      }
    }

    return false;
  }

  /// 현재 로컬에 등록된 삭제 보존작 총 개수 반환
  static Future<int> getExpungedCount() async {
    try {
      final db = await getInstance();
      if (db == null || !db.isOpen) return 0;
      final rows = await db.rawQuery('SELECT COUNT(*) as count FROM HitomiColumnModel');
      if (rows.isNotEmpty) {
        return (rows.first['count'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// SQL 쿼리 수행 (rawQuery)
  static Future<List<Map<String, dynamic>>> query(String sqlQuery) async {
    try {
      final db = await getInstance();
      if (db == null || !db.isOpen) return [];
      return await db.rawQuery(sqlQuery);
    } catch (e, st) {
      Logger.error('[ExpungedDB] Query error: $e\n$st');
      return [];
    }
  }

  /// 특정 품번(Id)으로 삭제작 상세 정보 고속 단일 조회
  static Future<QueryResult?> queryId(int id) async {
    try {
      final db = await getInstance();
      if (db == null || !db.isOpen) return null;
      final rows = await db.rawQuery(
        'SELECT * FROM HitomiColumnModel WHERE Id = ? LIMIT 1',
        [id],
      );
      if (rows.isNotEmpty) {
        final map = Map<String, dynamic>.from(rows.first);
        map['source'] = 'common';
        map['is_common'] = true;
        map['is_expunged'] = true;
        return QueryResult(result: map);
      }
    } catch (_) {}
    return null;
  }
}
