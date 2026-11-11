// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:typed_data';
import 'dart:ui' as ui;

/// 썸네일 이미지의 8x8 지각적 차이 해시(dHash, Difference Hash)를 계산하고
/// 비트 단위 해밍 거리를 통해 시각적 유사도 점수를 산출하는 유틸리티
class ImagePerceptualHash {
  /// 썸네일 이미지 바이트(WebP, PNG, JPG 등)를 9x8로 초경량 디코딩하여
  /// 64비트 정수 dHash를 산출합니다.
  static Future<int?> computeDHashFromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 9,
        targetHeight: 8,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;

      // 8행 8열(인접 9열 비교) = 64비트 해시 생성
      int hash = 0;
      for (int row = 0; row < 8; row++) {
        for (int col = 0; col < 8; col++) {
          final leftLum = _luminance(byteData, (row * 9 + col) * 4);
          final rightLum = _luminance(byteData, (row * 9 + col + 1) * 4);

          hash = (hash << 1) | (leftLum > rightLum ? 1 : 0);
        }
      }
      return hash;
    } catch (_) {
      return null;
    }
  }

  static int _luminance(ByteData bd, int offset) {
    final r = bd.getUint8(offset);
    final g = bd.getUint8(offset + 1);
    final b = bd.getUint8(offset + 2);
    return (r * 299 + g * 587 + b * 114) ~/ 1000;
  }

  /// 64비트 정수에서 1의 비트 수(Hamming Weight)를 셉니다.
  static int popcount64(int x) {
    var v = x;
    int count = 0;
    for (int i = 0; i < 64; i++) {
      if ((v & 1) != 0) count++;
      v = (v >> 1) & 0x7FFFFFFFFFFFFFFF;
    }
    return count;
  }

  /// 두 64비트 dHash 간의 해밍 유사도 백분율 (0.0% ~ 100.0%)을 반환합니다.
  static double calculateSimilarity(int h1, int h2) {
    final diff = h1 ^ h2;
    final diffBits = popcount64(diff);
    return (1.0 - (diffBits / 64.0)) * 100.0;
  }
}
