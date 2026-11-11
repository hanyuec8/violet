// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:violet/algorithm/image_perceptual_hash.dart';
import 'package:violet/component/hitomi/hitomi_nozomi.dart';
import 'package:violet/src/rust/api/image_hash.dart' as rust_image_hash;
import 'package:violet/src/rust/api/nozomi.dart' as rust_nozomi;
import 'package:violet/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    if (Platform.isWindows) {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(
          'rust/target/debug/rust_lib_violet.dll',
        ),
      );
    }
  });

  group('[기능 1] Hitomi Nozomi 바이트 파서 (parseNozomiBytes)', () {
    test('1.1 표준 4바이트 Big-Endian 정수 파싱 정합성 검증', () {
      final bdata = ByteData(16);
      bdata.setUint32(0, 100, Endian.big);
      bdata.setUint32(4, 2000, Endian.big);
      bdata.setUint32(8, 3080152, Endian.big);
      bdata.setUint32(12, 4316732, Endian.big);

      final result = rust_nozomi.parseNozomiBytes(
        bytes: bdata.buffer.asUint8List(),
      );
      expect(result, equals([100, 2000, 3080152, 4316732]));
    });

    test('1.2 엣지 케이스: 빈 바이트 배열 입력 시 안전한 빈 리스트 반환', () {
      final result = rust_nozomi.parseNozomiBytes(bytes: []);
      expect(result, isEmpty);
    });

    test('1.3 엣지 케이스: 4바이트 배수가 아닌 불완전 바이트(11바이트) 입력 시 크래시 없이 온전한 청크만 파싱', () {
      final bdata = ByteData(11);
      bdata.setUint32(0, 1111, Endian.big);
      bdata.setUint32(4, 2222, Endian.big);
      // 나머지 3바이트는 쓰레기 데이터
      bdata.setUint8(8, 0xFF);
      bdata.setUint8(9, 0xFF);
      bdata.setUint8(10, 0xFF);

      final result = rust_nozomi.parseNozomiBytes(
        bytes: bdata.buffer.asUint8List(),
      );
      // chunks_exact(4)에 의해 2개만 안전하게 파싱됨
      expect(result, equals([1111, 2222]));
    });

    test('1.4 대용량 성능 벤치마크: 100,000건(400KB) 바이너리 파싱 속도 실측', () {
      const count = 100000;
      final bdata = ByteData(count * 4);
      for (var i = 0; i < count; i++) {
        bdata.setUint32(i * 4, 3000000 + i, Endian.big);
      }
      final rawBytes = bdata.buffer.asUint8List();

      final sw = Stopwatch()..start();
      final parsed = rust_nozomi.parseNozomiBytes(bytes: rawBytes);
      sw.stop();

      expect(parsed.length, equals(count));
      expect(parsed.first, equals(3000000));
      expect(parsed.last, equals(3000000 + count - 1));
      print('>> [벤치마크] parseNozomiBytes 100,000건 파싱 소요 시간: ${sw.elapsedMilliseconds}ms (${sw.elapsedMicroseconds}us)');
    });
  });

  group('[기능 2] 다중 태그 교집합 및 정렬 (intersectNozomiIds)', () {
    test('2.1 다중 태그(3개 리스트) 교집합 및 내림차순(최신순) 정렬 검증', () {
      final list1 = Uint32List.fromList([100, 200, 300, 400, 500]);
      final list2 = Uint32List.fromList([200, 400, 600, 800]);
      final list3 = Uint32List.fromList([400, 200, 999]);

      final result = rust_nozomi.intersectNozomiIds(
        lists: [list1, list2, list3],
      );
      // 교집합 원소 {200, 400} -> 최신순 내림차순 [400, 200]
      expect(result, equals([400, 200]));
    });

    test('2.2 엣지 케이스: 리스트 1개만 입력 시 중복 제거 및 내림차순 정렬', () {
      final list = Uint32List.fromList([10, 50, 20, 50, 30]);
      final result = rust_nozomi.intersectNozomiIds(lists: [list]);
      expect(result, equals([50, 30, 20, 10]));
    });

    test('2.3 엣지 케이스: 빈 리스트가 1개라도 포함된 경우 즉시 0건 반환', () {
      final list1 = Uint32List.fromList([100, 200]);
      final list2 = Uint32List.fromList([]);
      final list3 = Uint32List.fromList([100, 200, 300]);

      final result = rust_nozomi.intersectNozomiIds(
        lists: [list1, list2, list3],
      );
      expect(result, isEmpty);
    });

    test('2.4 엣지 케이스: 서로 교집합이 없는 경우 빈 리스트 반환', () {
      final list1 = Uint32List.fromList([1, 2, 3]);
      final list2 = Uint32List.fromList([4, 5, 6]);

      final result = rust_nozomi.intersectNozomiIds(lists: [list1, list2]);
      expect(result, isEmpty);
    });

    test('2.5 대용량 성능 벤치마크: 3개 태그(각각 10,000건, 교집합 1,500건) 고속 연산 실측', () {
      const size = 10000;
      final rand = Random(42);

      // 공통 교집합 1,500건
      final commonIds = List.generate(1500, (i) => 2000000 + i * 2);

      // 각 리스트 생성
      final list1 = Uint32List.fromList([
        ...commonIds,
        ...List.generate(size - 1500, (i) => 1000000 + rand.nextInt(500000)),
      ]);
      final list2 = Uint32List.fromList([
        ...commonIds,
        ...List.generate(size - 1500, (i) => 3000000 + rand.nextInt(500000)),
      ]);
      final list3 = Uint32List.fromList([
        ...commonIds,
        ...List.generate(size - 1500, (i) => 5000000 + rand.nextInt(500000)),
      ]);

      final sw = Stopwatch()..start();
      final intersection = rust_nozomi.intersectNozomiIds(
        lists: [list1, list2, list3],
      );
      sw.stop();

      expect(intersection.length, greaterThanOrEqualTo(1500));
      // 내림차순 정렬 여부 검증
      for (var i = 0; i < intersection.length - 1; i++) {
        expect(intersection[i], greaterThan(intersection[i + 1]));
      }
      print('>> [벤치마크] intersectNozomiIds 3x10,000건 교집합/정렬 소요 시간: ${sw.elapsedMilliseconds}ms (${sw.elapsedMicroseconds}us)');
    });
  });

  group('[기능 3] 이미지 지각적 해시 (computeDhash)', () {
    test('3.1 실제 이미지 파일로부터 64비트 dHash 생성 검증', () {
      final file = File('../testimage/japanese/Screenshot_20261031_155558.png');
      expect(file.existsSync(), isTrue);

      final bytes = file.readAsBytesSync();
      final sw = Stopwatch()..start();
      final hash = rust_image_hash.computeDhash(bytes: bytes);
      sw.stop();

      expect(hash, isNotNull);
      expect(hash, isA<BigInt>());
      print('>> [실측] 실제 만화 이미지(${bytes.length ~/ 1024}KB) dHash 생성: 0x${hash!.toRadixString(16).padLeft(16, '0')} (소요 시간: ${sw.elapsedMilliseconds}ms)');
    });

    test('3.2 엣지 케이스: 빈 바이트 배열 입력 시 안전하게 null 반환', () {
      final hash = rust_image_hash.computeDhash(bytes: []);
      expect(hash, isNull);
    });

    test('3.3 엣지 케이스: 손상된 바이트 입력 시 크래시 없이 null 반환', () {
      final corruptedBytes = [0xFF, 0xD8, 0xFF, 0x00, 0x12, 0x34];
      final hash = rust_image_hash.computeDhash(bytes: corruptedBytes);
      expect(hash, isNull);
    });
  });

  group('[기능 4] dHash 시각적 유사도 계산 (calculateDhashSimilarity)', () {
    test('4.1 동일한 해시 입력 시 정확히 100.0% 반환', () {
      final h1 = BigInt.parse('1010101010101010', radix: 2);
      final sim = rust_image_hash.calculateDhashSimilarity(h1: h1, h2: h1);
      expect(sim, equals(100.0));
    });

    test('4.2 64비트 전체 반전 해시 입력 시 0.0% 반환', () {
      final h1 = BigInt.zero;
      final h2 = (BigInt.one << 64) - BigInt.one; // 64비트 전체 1
      final sim = rust_image_hash.calculateDhashSimilarity(h1: h1, h2: h2);
      expect(sim, equals(0.0));
    });

    test('4.3 1비트 차이 시 63/64 = 98.4375% 정밀 계산 검증', () {
      final h1 = BigInt.zero;
      final h2 = BigInt.one; // 맨 마지막 1비트만 다름
      final sim = rust_image_hash.calculateDhashSimilarity(h1: h1, h2: h2);
      expect(sim, equals(98.4375));
    });

    test('4.4 실제 서로 다른 두 만화 이미지 간의 dHash 유사도 측정', () {
      final file1 = File('../testimage/japanese/Screenshot_20261031_155558.png');
      final file2 = File('../testimage/japanese/Screenshot_20261031_155659.png');

      final hash1 = rust_image_hash.computeDhash(bytes: file1.readAsBytesSync())!;
      final hash2 = rust_image_hash.computeDhash(bytes: file2.readAsBytesSync())!;

      final simSame = rust_image_hash.calculateDhashSimilarity(h1: hash1, h2: hash1);
      final simDiff = rust_image_hash.calculateDhashSimilarity(h1: hash1, h2: hash2);

      expect(simSame, equals(100.0));
      expect(simDiff, lessThan(100.0));
      expect(simDiff, greaterThanOrEqualTo(0.0));
      print('>> [실측] 이미지 1 dHash: 0x${hash1.toRadixString(16).padLeft(16, '0')}');
      print('>> [실측] 이미지 2 dHash: 0x${hash2.toRadixString(16).padLeft(16, '0')}');
      print('>> [실측] 두 이미지 간 dHash 시각적 유사도: ${simDiff.toStringAsFixed(2)}%');
    });
  });

  group('[기능 5] Dart 래퍼 클래스 통합 연동 (HitomiNozomi / ImagePerceptualHash)', () {
    test('5.1 HitomiNozomi.parseNozomiBytes를 통한 FFI 호출 검증', () {
      final bdata = ByteData(8);
      bdata.setUint32(0, 999999, Endian.big);
      bdata.setUint32(4, 888888, Endian.big);

      final ids = HitomiNozomi.parseNozomiBytes(bdata.buffer.asUint8List());
      expect(ids, equals([999999, 888888]));
    });

    test('5.2 ImagePerceptualHash.calculateSimilarity를 통한 FFI 호출 검증', () {
      final sim = ImagePerceptualHash.calculateSimilarity(0x12345678, 0x12345678);
      expect(sim, equals(100.0));
    });
  });
}
