import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:violet/update/update_manager.dart';

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.current.path;
      },
    );
  });

  test('UpdateManager.clearUpdateCache removes only .apk files in temporary directory', () async {
    final tempDir = await getTemporaryDirectory();
    final apkFile1 = File('${tempDir.path}/violet_update_1.34.4.apk');
    final apkFile2 = File('${tempDir.path}/test_download.APK');
    final otherFile = File('${tempDir.path}/keep_this_file.txt');

    await apkFile1.writeAsString('fake apk binary content 1');
    await apkFile2.writeAsString('fake apk binary content 2');
    await otherFile.writeAsString('this text file must be preserved');

    expect(await apkFile1.exists(), true);
    expect(await apkFile2.exists(), true);
    expect(await otherFile.exists(), true);

    // clearUpdateCache 실행
    await UpdateManager.clearUpdateCache();

    // APK 파일들은 전량 삭제되어야 함
    expect(await apkFile1.exists(), false, reason: 'apkFile1 must be deleted');
    expect(await apkFile2.exists(), false, reason: 'apkFile2 must be deleted (case-insensitive)');

    // 비 APK 파일은 보존되어야 함
    expect(await otherFile.exists(), true, reason: 'otherFile must be preserved');

    // 테스트 후 정리
    if (await otherFile.exists()) {
      await otherFile.delete();
    }
  });
}
