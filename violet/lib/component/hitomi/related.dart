// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:path/path.dart';

class Related {
  static Map<int, List<int>>? _related;
  static bool _isLoading = false;

  static bool get isLoaded => _related != null;
  static Map<int, List<int>> get related => _related ?? const {};

  static Future<void> init() async {
    await ensureLoaded();
  }

  static Future<void> ensureLoaded() async {
    if (_related != null || _isLoading) return;
    _isLoading = true;

    try {
      String data;
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final file = File(
          join(Directory.current.path, 'assets/rank/related.json'),
        );
        data = await file.readAsString();
      } else {
        data = await rootBundle.loadString('assets/rank/related.json');
      }

      Future<Map<int, List<int>>> decodeJsonData() async {
        final related = <int, List<int>>{};

        json.decode(
          data,
          reviver: (key, value) {
            if (key == null) {
              return value;
            }

            if (key is String) {
              related[int.parse(key)] = (value as List<dynamic>).cast();
              return null;
            } else {
              return value;
            }
          },
        );

        return related;
      }

      _related = await Isolate.run(decodeJsonData);
    } catch (_) {
      _related = {};
    } finally {
      _isLoading = false;
    }
  }

  static bool existsRelated(int articleId) {
    if (_related == null) {
      ensureLoaded();
      return false;
    }
    return _related!.containsKey(articleId);
  }

  static List<int> getRelated(int articleId) {
    if (_related == null) return const [];
    return _related![articleId] ?? const [];
  }
}
