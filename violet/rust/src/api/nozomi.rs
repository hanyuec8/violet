// This source code is a part of Project Violet.
// Copyright (C) 2020-2026. violet-team. Licensed under the Apache-2.0 License.

use ahash::AHashSet;

/// Hitomi Nozomi .nozomi 바이너리 바이트(4바이트 Big-Endian ID 배열)를 고속 파싱하여 `Vec<u32>`로 반환합니다.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_nozomi_bytes(bytes: Vec<u8>) -> Vec<u32> {
    let count = bytes.len() / 4;
    let mut ids = Vec::with_capacity(count);

    for chunk in bytes.chunks_exact(4) {
        let id = u32::from_be_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
        ids.push(id);
    }

    ids
}

/// 복수 개의 Nozomi ID 리스트들을 입력받아 교집합(Intersection)을 고속 산출하고
/// 최신순(내림차순)으로 정렬하여 반환합니다.
#[flutter_rust_bridge::frb(sync)]
pub fn intersect_nozomi_ids(lists: Vec<Vec<u32>>) -> Vec<u32> {
    if lists.is_empty() {
        return Vec::new();
    }

    // 어느 하나라도 0건이면 교집합 결과는 0건
    if lists.iter().any(|list| list.is_empty()) {
        return Vec::new();
    }

    if lists.len() == 1 {
        let mut single = lists.into_iter().next().unwrap();
        single.sort_unstable_by(|a, b| b.cmp(a));
        single.dedup();
        return single;
    }

    // 가장 길이가 짧은 리스트를 찾아 기준으로 설정하여 메모리 및 연산 최소화
    let mut sorted_by_len = lists;
    sorted_by_len.sort_by_key(|l| l.len());

    let first = sorted_by_len.remove(0);
    let mut current_set: AHashSet<u32> = first.into_iter().collect();

    for other_list in sorted_by_len {
        let other_set: AHashSet<u32> = other_list.into_iter().collect();
        current_set.retain(|id| other_set.contains(id));
        if current_set.is_empty() {
            return Vec::new();
        }
    }

    let mut result: Vec<u32> = current_set.into_iter().collect();
    result.sort_unstable_by(|a, b| b.cmp(a));
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_nozomi_bytes() {
        // ID 1 (0x00000001)과 ID 3080152 (0x002EFFD8)
        let mut bytes = Vec::new();
        bytes.extend_from_slice(&1u32.to_be_bytes());
        bytes.extend_from_slice(&3080152u32.to_be_bytes());

        let parsed = parse_nozomi_bytes(bytes);
        assert_eq!(parsed, vec![1, 3080152]);
    }

    #[test]
    fn test_intersect_nozomi_ids() {
        let list1 = vec![100, 200, 300, 400];
        let list2 = vec![200, 400, 500];
        let list3 = vec![400, 600, 200];

        let result = intersect_nozomi_ids(vec![list1, list2, list3]);
        // 내림차순 정렬 검증
        assert_eq!(result, vec![400, 200]);

        // 빈 리스트가 포함된 경우
        let empty_result = intersect_nozomi_ids(vec![vec![1, 2], vec![]]);
        assert!(empty_result.is_empty());
    }
}
