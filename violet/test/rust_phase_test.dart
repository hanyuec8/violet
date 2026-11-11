// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

import 'dart:io';

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

  group('Phase 1: Nozomi Parser & Intersection Rust Tests', () {
    test('parseNozomiBytes converts big-endian bytes to gallery IDs correctly', () {
      final bdata = ByteData(8);
      bdata.setUint32(0, 123456, Endian.big);
      bdata.setUint32(4, 3080152, Endian.big);

      final ids = HitomiNozomi.parseNozomiBytes(bdata.buffer.asUint8List());
      expect(ids, equals([123456, 3080152]));
    });

    test('intersectNozomiIds returns intersection in descending order', () {
      final list1 = Uint32List.fromList([100, 200, 300, 400]);
      final list2 = Uint32List.fromList([200, 400, 500]);
      final list3 = Uint32List.fromList([400, 600, 200]);

      final intersection = rust_nozomi.intersectNozomiIds(
        lists: [list1, list2, list3],
      );
      expect(intersection, equals([400, 200]));
    });

    test('intersectNozomiIds returns empty when any list is empty', () {
      final list1 = Uint32List.fromList([1, 2, 3]);
      final list2 = Uint32List.fromList([]);

      final intersection = rust_nozomi.intersectNozomiIds(
        lists: [list1, list2],
      );
      expect(intersection, isEmpty);
    });
  });

  group('Phase 3: Image Perceptual Hash Rust Tests', () {
    test('calculateSimilarity computes exact hamming percentage', () {
      final h1 = 0xAAAAAAAAAAAAAAAA;
      final h2 = 0xAAAAAAAAAAAAAAAA;
      expect(ImagePerceptualHash.calculateSimilarity(h1, h2), equals(100.0));

      final h3 = ~h1;
      expect(ImagePerceptualHash.calculateSimilarity(h1, h3), equals(0.0));
    });

    test('computeDhash returns null for invalid/empty bytes safely', () {
      final emptyRes = rust_image_hash.computeDhash(bytes: []);
      expect(emptyRes, isNull);

      final invalidRes = rust_image_hash.computeDhash(bytes: [1, 2, 3, 4]);
      expect(invalidRes, isNull);
    });
  });
}
