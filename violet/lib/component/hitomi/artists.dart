// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart';

class Artists {
  static Map<Map<String, dynamic>, dynamic> collection =
      <Map<String, dynamic>, dynamic>{};

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    try {
      String data;
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final file = File(
          join(Directory.current.path, 'assets/artists_collection.json'),
        );
        data = await file.readAsString();
      } else {
        data = await rootBundle.loadString('assets/artists_collection.json');
      }

      final List<dynamic> parsed = json.decode(data) as List<dynamic>;
      final map = <Map<String, dynamic>, dynamic>{};

      for (final entry in parsed) {
        if (entry is Map<String, dynamic>) {
          final header = entry['header'] as Map<String, dynamic>? ?? {};
          final artists = (entry['artists'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              <String>[];
          map[header] = artists;
        }
      }

      collection = map;
      _initialized = true;
    } catch (_) {}
  }
}
