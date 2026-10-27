// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'package:violet/settings/settings.dart';

/// Translate search query to sql query
String translate2query(String query, {bool filter = true}) {
  query = query.trim();
  final tokens = _splitTokens(
    query,
  ).map((x) => x.trim()).where((x) => x != '').toList();

  final filterExistsOnHitomi = !Settings.searchPure.value && filter;

  if (tokens.isEmpty) {
    return 'SELECT * FROM HitomiColumnModel ${filterExistsOnHitomi ? "WHERE ExistOnHitomi=1" : ""}';
  }

  // 순수 숫자(단일 품번) 단독 검색인 경우 고속 직결
  if (tokens.length == 1) {
    final nn = int.tryParse(tokens[0]);
    if (nn != null) {
      return 'SELECT * FROM HitomiColumnModel WHERE Id=$nn';
    }
  }

  final where = _QueryTranslator(tokens).parseExpression().trim();

  if (where.isEmpty) {
    return 'SELECT * FROM HitomiColumnModel ${filterExistsOnHitomi ? "WHERE ExistOnHitomi=1" : ""}';
  }

  return 'SELECT * FROM HitomiColumnModel WHERE ($where) ${filterExistsOnHitomi ? " AND ExistOnHitomi=1" : ""}';
}

List<String> _splitTokens(String tokens) {
  final result = <String>[];
  final builder = StringBuffer();
  for (int i = 0; i < tokens.length; i++) {
    if (tokens[i] == ' ') {
      result.add(builder.toString());
      builder.clear();
      continue;
    } else if (tokens[i] == '(' || tokens[i] == ')') {
      result.add(builder.toString());
      builder.clear();
      result.add(tokens[i]);
      continue;
    }

    builder.write(tokens[i]);
  }

  result.add(builder.toString());
  return result;
}

class _QueryTranslator {
  final List<String> tokens;
  int index = 0;

  _QueryTranslator(this.tokens);

  String parseExpression() {
    if (index >= tokens.length) return '';

    String token = nextToken();
    var where = '';
    bool negative = false;

    if (token.startsWith('-')) {
      negative = true;
      if (token == '-') {
        token = nextToken();
      } else {
        token = token.substring(1);
      }
    }

    if (token.startsWith('page') &&
        (token.contains('>') || token.contains('=') || token.contains('<'))) {
      where += parsePageExpression(token, negative);
    } else if (token.startsWith('id') &&
        (token.contains('>') || token.contains('=') || token.contains('<'))) {
      where += parseIdExpression(token, negative);
    } else if ((token.startsWith('date') || token.startsWith('published')) &&
        (token.contains('>') || token.contains('=') || token.contains('<'))) {
      where += parseDateExpression(token, negative);
    } else if (token.contains(':')) {
      where += parseTag(token, negative);
    } else if (token == 'random') {
      // random 단독 토큰은 WHERE 절에서 무시 (ORDER BY에서 처리)
      where += '';
    } else if (token == '(') {
      final inner = parseExpression();
      if (hasMoreTokens()) nextToken();
      where += negative ? 'NOT ($inner)' : '($inner)';
      if (hasMoreTokens() && lookAhead() != ')') {
        final logic = parseLogicalExpression();
        if (logic.isNotEmpty) where += logic;
      }
      return where;
    } else if (token == ')') {
      return token;
    } else {
      where += parseTitle(token, negative);
    }

    if (where.trim().isEmpty) {
      if (hasMoreTokens() && lookAhead() != ')') {
        return parseExpression();
      }
      return '';
    }

    if (hasMoreTokens() && lookAhead() != ')') {
      final logic = parseLogicalExpression();
      if (logic.isNotEmpty) where += logic;
    }

    return where;
  }

  String parseTag(String token, bool negative) {
    var ss = token.split(':');
    final tagType = ss[0].toLowerCase();

    // random:seed 무시 (ORDER BY에서 처리)
    if (tagType == 'random') return '';

    // 번호 구간 (id:1000~2000, id:1000..2000, id:1000-2000, id:1000)
    if (tagType == 'id') {
      final rangeMatch = RegExp(r'^id:(\d+)(?:~|\.\.|\-)(\d+)$', caseSensitive: false).firstMatch(token);
      if (rangeMatch != null) {
        final start = rangeMatch.group(1)!;
        final end = rangeMatch.group(2)!;
        return negative ? '(Id < $start OR Id > $end)' : '(Id >= $start AND Id <= $end)';
      }
      final singleMatch = RegExp(r'^id:(\d+)$', caseSensitive: false).firstMatch(token);
      if (singleMatch != null) {
        final idVal = singleMatch.group(1)!;
        return negative ? 'Id != $idVal' : 'Id = $idVal';
      }
      return '';
    }

    // 날짜 구간 (date:2023-01-01~2024-01-01, date:2023~2024, published:...)
    if (tagType == 'date' || tagType == 'published') {
      final dateRangeMatch = RegExp(r'^(?:date|published):(\d{4}(?:-\d{2}-\d{2})?)(?:~|\.\.)(\d{4}(?:-\d{2}-\d{2})?)$', caseSensitive: false).firstMatch(token);
      if (dateRangeMatch != null) {
        var start = dateRangeMatch.group(1)!;
        var end = dateRangeMatch.group(2)!;
        if (start.length == 4) start = '$start-01-01';
        if (end.length == 4) end = '$end-12-31';
        return negative
            ? "(Published < '$start' OR Published > '$end 23:59:59')"
            : "(Published >= '$start' AND Published <= '$end 23:59:59')";
      }
      final singleDateMatch = RegExp(r'^(?:date|published):(\d{4}(?:-\d{2}-\d{2})?)$', caseSensitive: false).firstMatch(token);
      if (singleDateMatch != null) {
        final d = singleDateMatch.group(1)!;
        if (d.length == 4) {
          return negative
              ? "(Published < '$d-01-01' OR Published > '$d-12-31 23:59:59')"
              : "(Published >= '$d-01-01' AND Published <= '$d-12-31 23:59:59')";
        } else {
          return negative
              ? "(Published NOT LIKE '$d%')"
              : "(Published LIKE '$d%')";
        }
      }
      return '';
    }

    var column = findColumnByTag(tagType);
    if (column == '') return '';

    var name = '';
    switch (tagType) {
      case 'male':
      case 'female':
        name = '|${token.replaceAll('_', ' ')}|';
        break;

      case 'tag':
      case 'series':
      case 'character':
        name = '|${ss[1].replaceAll('_', ' ')}|';
        break;

      case 'artist':
      case 'group':
        // 성/이름 단독 검색(artist:tadataka) 부분 일치 지원
        name = ss[1].replaceAll('_', ' ');
        break;

      case 'uploader':
        name = ss[1];
        break;

      case 'lang':
      case 'language':
      case 'type':
      case 'class':
        name = ss[1].replaceAll('_', ' ');
        break;
    }

    var compare = "$column LIKE '%$name%'";
    if (column == 'Uploader') compare += ' COLLATE NOCASE';

    return (negative ? '($compare) IS NOT 1' : compare);
  }

  String parsePageExpression(String token, bool negative) {
    final re = RegExp(r'page([\=\<\>]{1,2})(\d+)', caseSensitive: false);
    if (re.hasMatch(token)) {
      final matches = re.allMatches(token).elementAt(0);
      final op = matches.group(1)!;
      final val = matches.group(2)!;
      if (negative) {
        final negOp = op == '>=' ? '<' : op == '<=' ? '>' : op == '>' ? '<=' : op == '<' ? '>=' : '!=';
        return 'Files $negOp $val';
      }
      return 'Files $op $val';
    }
    return '';
  }

  String parseIdExpression(String token, bool negative) {
    final re = RegExp(r'id([\=\<\>]{1,2})(\d+)', caseSensitive: false);
    if (re.hasMatch(token)) {
      final matches = re.allMatches(token).elementAt(0);
      final op = matches.group(1)!;
      final val = matches.group(2)!;
      if (negative) {
        final negOp = op == '>=' ? '<' : op == '<=' ? '>' : op == '>' ? '<=' : op == '<' ? '>=' : '!=';
        return 'Id $negOp $val';
      }
      return 'Id $op $val';
    }
    return '';
  }

  String parseDateExpression(String token, bool negative) {
    final re = RegExp(r'(?:date|published)([\=\<\>]{1,2})(\d{4}(?:-\d{2}-\d{2})?)', caseSensitive: false);
    if (re.hasMatch(token)) {
      final matches = re.allMatches(token).elementAt(0);
      final op = matches.group(1)!;
      var val = matches.group(2)!;
      if (val.length == 4) {
        if (op.contains('>')) {
          val = '$val-01-01';
        } else if (op.contains('<')) {
          val = '$val-12-31 23:59:59';
        } else {
          return negative
              ? "(Published < '$val-01-01' OR Published > '$val-12-31 23:59:59')"
              : "(Published >= '$val-01-01' AND Published <= '$val-12-31 23:59:59')";
        }
      } else {
        if (op.contains('<') && !val.contains(':')) {
          val = '$val 23:59:59';
        }
      }
      if (negative) {
        final negOp = op == '>=' ? '<' : op == '<=' ? '>' : op == '>' ? '<=' : op == '<' ? '>=' : '!=';
        return "Published $negOp '$val'";
      }
      return "Published $op '$val'";
    }
    return '';
  }

  String parseParentheses(String token, bool negative) {
    return negative ? 'NOT $token' : token;
  }

  String parseTitle(String token, bool negative) {
    return negative ? "Title NOT LIKE '%$token%'" : "Title LIKE '%$token%'";
  }

  String parseLogicalExpression() {
    String next = lookAhead();
    late String op;
    if (next.toLowerCase() == 'or') {
      nextToken();
      op = 'OR';
    } else {
      op = 'AND';
    }
    final nextExpr = parseExpression().trim();
    if (nextExpr.isEmpty) return '';
    return ' $op $nextExpr';
  }

  String nextToken() => tokens[index++];
  String lookAhead() => index < tokens.length ? tokens[index] : '';
  bool hasMoreTokens() => index < tokens.length;

  static String findColumnByTag(String tag) {
    switch (tag) {
      case 'male':
      case 'female':
      case 'tag':
        return 'Tags';

      case 'lang':
      case 'language':
        return 'Language';

      case 'series':
        return 'Series';

      case 'artist':
        return 'Artists';

      case 'group':
        return 'Groups';

      case 'uploader':
        return 'Uploader';

      case 'character':
        return 'Characters';

      case 'type':
        return 'Type';

      case 'class':
        return 'Class';
    }

    return tag;
  }
}
