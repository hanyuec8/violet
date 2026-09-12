// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/download.dart';

class Population {
  static Map<int, int>? _population;
  static bool _isLoading = false;

  static bool get isLoaded => _population != null;
  static Map<int, int> get population => _population ?? const {};

  static Future<void> init() async {
    await ensureLoaded();
  }

  static Future<void> ensureLoaded() async {
    if (_population != null || _isLoading) return;
    _isLoading = true;

    try {
      String data;
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final file = File(
          join(Directory.current.path, 'assets/rank/population.json'),
        );
        data = await file.readAsString();
      } else {
        data = await rootBundle.loadString('assets/rank/population.json');
      }

      Future<Map<int, int>> decodeJsonData() async {
        final population = <int, int>{};

        json.decode(
          data,
          reviver: (keyObject, valueObject) {
            if (keyObject == null) {
              return null;
            }

            int key = keyObject as int;
            int value = (valueObject as num).toInt();

            population[value] = key;

            return null;
          },
        );

        return population;
      }

      _population = await Isolate.run(decodeJsonData);
    } catch (_) {
      _population = {};
    } finally {
      _isLoading = false;
    }
  }

  static void sortByPopulation(List<QueryResult> qr) {
    if (_population == null) {
      ensureLoaded();
      return;
    }
    qr.sort((x, y) => compare(x, y));
  }

  static void sortByPopulationDownloadItem(List<DownloadItemModel> qr) {
    if (_population == null) {
      ensureLoaded();
      return;
    }
    qr.sort((x, y) => compareDownloadItem(x, y));
  }

  static int compare(QueryResult a, QueryResult b) {
    if (_population == null) return 0;
    // newest article always displayed on the bottom
    if (!_population!.containsKey(a.id())) {
      // a == b
      if (!_population!.containsKey(b.id())) return 0;
      // a > b
      return 1;
    }
    // a < b
    if (!_population!.containsKey(b.id())) return -1;

    return _population![a.id()]!.compareTo(_population![b.id()]!);
  }

  static int compareDownloadItem(DownloadItemModel a, DownloadItemModel b) {
    if (_population == null) return 0;
    // newest article always displayed on the bottom
    if (!_population!.containsKey(a.id())) {
      // a == b
      if (!_population!.containsKey(b.id())) return 0;
      // a > b
      return 1;
    }
    // a < b
    if (!_population!.containsKey(b.id())) return -1;

    return _population![a.id()]!.compareTo(_population![b.id()]!);
  }
}
