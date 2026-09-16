// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:violet/component/index.dart';
import 'package:violet/database/database.dart';
import 'package:violet/settings/settings.dart';

class QueryResult {
  Map<String, dynamic> result;
  QueryResult({required this.result});

  int id() => result['Id'];
  title() => result['Title'] ?? '';
  ehash() => result['EHash'];
  type() => result['Type'];
  artists() => result['Artists'] ?? '';
  characters() => result['Characters'];
  groups() => result['Groups'];
  language() => result['Language'];
  series() => result['Series'];
  tags() => result['Tags'];
  uploader() => result['Uploader'];
  published() => result['Published'];
  files() => result['Files'];
  classname() => result['Class'];

  // For E/Ex Hentai
  publishedeh() => result['PublishedEH'];
  thumbnail() => result['Thumbnail'];
  url() => result['URL'];


  DateTime? getDateTime() {
    final pub = published();
    if (pub == null || pub == 0 || pub == '') {
      final eh = publishedeh();
      if (eh != null && eh != '' && eh != 0) {
        return DateTime.tryParse(eh.toString());
      }
      return null;
    }

    if (pub is int || int.tryParse(pub.toString()) != null) {
      final intVal = pub is int ? pub : int.parse(pub.toString());
      const epochTicks = 621355968000000000;
      const ticksPerMillisecond = 10000;

      final ticksSinceEpoch = intVal - epochTicks;
      final ms = ticksSinceEpoch ~/ ticksPerMillisecond;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }

    final str = pub.toString().trim();
    final direct = DateTime.tryParse(str);
    if (direct != null) return direct;

    if (!str.contains('+') && !RegExp(r'-\d{2}').hasMatch(str) && !str.endsWith('Z')) {
      final withZ = DateTime.tryParse('${str}Z');
      if (withZ != null) return withZ;
    }

    return DateTime.tryParse('${str.replaceAll('+00:00', '')}Z');
  }

  // group, name
  List<(String, String)> tagList() {
    if (tags() == null) return [];

    var tagList = (tags() as String)
        .split('|')
        .where((element) => element != '')
        .map(
          (e) => (
            e.contains(':') ? e.split(':')[0] : 'tags',
            e.contains(':') ? e.split(':')[1] : e,
          ),
        )
        .toList();

    tagList.sort((a, b) {
      final groupOrder = const ['male', 'female'];

      final ga = groupOrder.indexOf(a.$1);
      final gb = groupOrder.indexOf(b.$1);
      if (ga != gb) return ga.compareTo(gb);

      final na = HentaiIndex.tagCount?[a.$1]?[a.$2] ?? 0;
      final nb = HentaiIndex.tagCount?[b.$1]?[b.$2] ?? 0;
      return na.compareTo(nb);
    });

    return tagList.reversed.toList();
  }
}

class QueryManager {
  String? queryString;
  List<QueryResult>? results;
  bool isPagination = false;
  int curPage = 0;
  int itemsPerPage = 500;

  static Future<QueryManager> query(String rawQuery) async {
    QueryManager qm = QueryManager();
    qm.queryString = rawQuery;
    qm.results = (await (await DataBaseManager.getInstance()).query(
      rawQuery,
    )).map((e) => QueryResult(result: e)).toList();
    return qm;
  }

  static QueryManager queryPagination(String rawQuery, int itemsPerPage) {
    QueryManager qm = QueryManager();
    qm.isPagination = true;
    qm.curPage = 0;
    qm.queryString = rawQuery;
    qm.itemsPerPage = itemsPerPage;
    return qm;
  }

  Future<List<QueryResult>> next() async {
    curPage += 1;
    return (await (await DataBaseManager.getInstance()).query(
      '$queryString ORDER BY Id DESC LIMIT $itemsPerPage OFFSET ${itemsPerPage * (curPage - 1)}',
    )).map((e) => QueryResult(result: e)).toList();
  }

  static Future<List<QueryResult>> queryIds<T>(List<T> ids) async {
    var queryRaw = 'SELECT * FROM HitomiColumnModel WHERE ';
    queryRaw += 'Id IN (${ids.join(',')})';
    var qm = await QueryManager.query(
      queryRaw + (!Settings.searchPure.value ? ' AND ExistOnHitomi=1' : ''),
    );

    var qr = <String, QueryResult>{};
    for (var element in qm.results!) {
      qr[element.id().toString()] = element;
    }

    var rr = ids
        .where((e) => qr.containsKey(e.toString()))
        .map((e) => qr[e.toString()]!)
        .toList();

    return rr;
  }
}
