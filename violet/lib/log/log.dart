// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart' as sync;

class LogEvent {
  DateTime? dateTime;
  bool isError;
  bool isWarning;
  String title;
  String message;
  String? detail;

  LogEvent({
    this.dateTime,
    this.isError = false,
    this.isWarning = false,
    required this.title,
    required this.message,
    this.detail,
  }) {
    dateTime ??= DateTime.now();
  }

  LogEvent copy() => LogEvent(
    dateTime: dateTime,
    isError: isError,
    isWarning: isWarning,
    title: title,
    message: message,
    detail: detail,
  );

  bool isHttpRequest() =>
      message.startsWith('GET:') || message.startsWith('GETS:');
}

class Logger {
  // Since isolates handle all asynchronous operations linearly,
  // there is no need for mutual exclusion.
  static sync.Lock lock = sync.Lock();
  static late File logFile;
  static List<LogEvent> events = <LogEvent>[];

  static int sessionStartByteOffset = 0;
  static DateTime sessionStartTime = DateTime.now().toUtc();

  static Future<void> init() async {
    sessionStartTime = DateTime.now().toUtc();

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      logFile = File('log.txt');
    } else {
      final dir = await getApplicationDocumentsDirectory();
      logFile = File(join(dir.path, 'log.txt'));
    }

    if (!await logFile.exists()) {
      await logFile.create();
      sessionStartByteOffset = 0;
    } else {
      final len = await logFile.length();
      // 기존 로그 파일이 5MB를 초과하여 비대해진 경우 최근 1MB만 남기고 안전하게 정리
      if (len > 5 * 1024 * 1024) {
        try {
          final raf = await logFile.open(mode: FileMode.read);
          await raf.setPosition(len - 1024 * 1024);
          final tailBytes = await raf.read(1024 * 1024);
          await raf.close();
          await logFile.writeAsBytes(tailBytes, mode: FileMode.write);
          sessionStartByteOffset = await logFile.length();
        } catch (_) {
          sessionStartByteOffset = len;
        }
      } else {
        sessionStartByteOffset = len;
      }
    }
  }

  static Future<void> log(String msg) async {
    print(msg);

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      await lock.synchronized(() async {
        await logFile.writeAsString(
          '[${DateTime.now().toUtc()}] $msg\n',
          mode: FileMode.append,
        );
      });
    }
  }

  static Future<void> _logMessage(
    String msg,
    String prefix,
    bool isError,
    bool isWarning,
  ) async {
    var message =
        (msg.startsWith('[') ? msg.substring(msg.indexOf(']') + 1) : msg)
            .trim();
    events.add(
      LogEvent(
        dateTime: DateTime.now().toUtc(),
        isError: isError,
        isWarning: isWarning,
        message: message.length > 500
            ? '${message.substring(0, 500)}...'
            : message,
        detail: message.length > 500 ? message : null,
        title:
            '[$prefix] (${DateFormat('kk:mm').format(DateTime.now())}) ${msg.startsWith('[') ? msg.split('[')[1].split(']')[0] : ''}',
      ),
    );
    await log('[$prefix] $msg');
  }

  static Future<void> info(String msg) async {
    await _logMessage(msg, 'Info', false, false);
  }

  static Future<void> error(String msg) async {
    await _logMessage(msg, 'Error', true, false);
  }

  static Future<void> warning(String msg) async {
    await _logMessage(msg, 'Warning', false, true);
  }

  static Future<void> showLogs() async {
    for (var element in (await logFile.readAsLines())) {
      print(element);
    }
  }

  static Future<File> getExportLogFile() async {
    final Directory exportDir;
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      exportDir = await getTemporaryDirectory();
    } else {
      exportDir = Directory.current;
    }

    final exportFile = File(join(exportDir.path, 'session_export_log.txt'));
    if (await exportFile.exists()) {
      await exportFile.delete();
    }
    await exportFile.create(recursive: true);

    // 1) logFile에서 sessionStartByteOffset 이후의 이번 세션 신규 로그 바이트만 추출
    List<int> newBytes = [];
    if (await logFile.exists()) {
      final curLen = await logFile.length();
      if (curLen > sessionStartByteOffset) {
        final raf = await logFile.open(mode: FileMode.read);
        await raf.setPosition(sessionStartByteOffset);
        newBytes = await raf.read(curLen - sessionStartByteOffset);
        await raf.close();
      }
    }

    // 2) 추출된 신규 세션 로그를 내보내기 파일에 저장
    if (newBytes.isNotEmpty) {
      await exportFile.writeAsBytes(newBytes);
    } else {
      // 신규 로그가 비어있는 경우 메모리 내 이번 세션 events 기반으로 생성
      final buffer = StringBuffer();
      buffer.writeln('=== Violet Session Log (${sessionStartTime.toIso8601String()}) ===');
      for (final e in events) {
        final dt = e.dateTime?.toIso8601String() ?? DateTime.now().toIso8601String();
        buffer.writeln('[$dt] ${e.title} ${e.message}');
        if (e.detail != null) {
          buffer.writeln('Detail: ${e.detail}');
        }
      }
      await exportFile.writeAsString(buffer.toString());
    }

    return exportFile;
  }

  static Future<void> exportLog() async {
    final ext = Platform.isIOS
        ? await getApplicationSupportDirectory()
        : await getExternalStorageDirectory();
    final extpath = '${ext!.path}/log.txt';
    final file = await getExportLogFile();
    await file.copy(extpath);
  }
}
