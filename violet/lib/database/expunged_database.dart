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
import 'package:violet/settings/settings.dart';

class ExpungedDatabaseManager {
  static Database? _db;
  static final Lock _lock = Lock();

  static bool get isOpen => _db != null && _db!.isOpen;

  static Future<Database?> getInstance() async {
    if (!Settings.searchExpunged.value) return null;

    if (_db != null && _db!.isOpen) return _db;

    await _lock.synchronized(() async {
      if (_db != null && _db!.isOpen) return;

      try {
        String dbPath;
        if (Platform.environment.containsKey('FLUTTER_TEST')) {
          dbPath = join(Directory.current.path, 'assets/database/expunged.db');
          if (!File(dbPath).existsSync()) {
            dbPath = join(Directory.current.path, '../expunged.db');
          }
        } else {
          final dir = await getApplicationDocumentsDirectory();
          final dataDir = Directory(join(dir.path, 'data'));
          if (!await dataDir.exists()) {
            await dataDir.create(recursive: true);
          }
          dbPath = join(dataDir.path, 'expunged.db');

          final dbFile = File(dbPath);
          if (!await dbFile.exists() || await dbFile.length() == 0) {
            Logger.info('[ExpungedDB] Copying expunged.db from assets...');
            final data = await rootBundle.load('assets/database/expunged.db');
            final bytes =
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
            await dbFile.writeAsBytes(bytes, flush: true);
            Logger.info('[ExpungedDB] Copy completed (${bytes.length} bytes)');
          }
        }

        if (File(dbPath).existsSync()) {
          _db = await openReadOnlyDatabase(dbPath);
          Logger.info('[ExpungedDB] Opened successfully at $dbPath');
        }
      } catch (e, st) {
        Logger.error('[ExpungedDB] Init error: $e\n$st');
      }
    });

    return _db;
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
