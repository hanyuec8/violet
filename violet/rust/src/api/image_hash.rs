// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

use image::imageops::FilterType;

/// 썸네일 이미지 바이트(WebP, PNG, JPEG 등)로부터 64비트 지각적 차이 해시(dHash, Difference Hash)를 계산합니다.
/// 이미지를 9x8 그레이스케일로 다운샘플링한 후, 인접 픽셀 밝기 비교를 통해 64비트 u64를 산출합니다.
#[flutter_rust_bridge::frb(sync)]
pub fn compute_dhash(bytes: Vec<u8>) -> Option<u64> {
    if bytes.is_empty() {
        return None;
    }

    let img = match image::load_from_memory(&bytes) {
        Ok(img) => img,
        Err(_) => return None,
    };

    // 9x8 그레이스케일 다운샘플링
    let luma = img
        .resize_exact(9, 8, FilterType::Triangle)
        .to_luma8();

    let mut hash: u64 = 0;
    for row in 0..8 {
        for col in 0..8 {
            let left = luma.get_pixel(col, row)[0];
            let right = luma.get_pixel(col + 1, row)[0];

            hash = (hash << 1) | if left > right { 1 } else { 0 };
        }
    }

    Some(hash)
}

/// 두 64비트 dHash 간의 해밍 거리(Hamming Distance)를 기반으로 시각적 유사도 백분율(0.0% ~ 100.0%)을 반환합니다.
#[flutter_rust_bridge::frb(sync)]
pub fn calculate_dhash_similarity(h1: u64, h2: u64) -> f64 {
    let diff_bits = (h1 ^ h2).count_ones();
    (1.0 - (diff_bits as f64 / 64.0)) * 100.0
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, Rgb};

    #[test]
    fn test_calculate_dhash_similarity() {
        let h1: u64 = 0b10101010;
        let h2: u64 = 0b10101010;
        assert_eq!(calculate_dhash_similarity(h1, h2), 100.0);

        let h3: u64 = !h1; // 64비트 전체 반전
        assert_eq!(calculate_dhash_similarity(h1, h3), 0.0);
    }

    #[test]
    fn test_compute_dhash_synthetic_image() {
        // 간단한 18x16 그라디언트 PNG 이미지 생성
        let mut img: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::new(18, 16);
        for (x, _y, pixel) in img.enumerate_pixels_mut() {
            let val = (x * 14) as u8;
            *pixel = Rgb([val, val, val]);
        }

        let mut png_bytes = Vec::new();
        img.write_to(
            &mut std::io::Cursor::new(&mut png_bytes),
            image::ImageFormat::Png,
        )
        .unwrap();

        let hash = compute_dhash(png_bytes);
        assert!(hash.is_some());
    }
}
