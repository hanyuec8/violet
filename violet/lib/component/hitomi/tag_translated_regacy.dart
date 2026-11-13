// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

/// 레거시 태그/시리즈 한국어 번역 폴백 매퍼 (assets/locale/tag/tag_legacy.json 기반)
class TagTranslatedRegacy {
  static Map<String, String> tagMap = <String, String>{};
  static Map<String, String> seriesMap = <String, String>{};

  static String mapTag2Kor(String tag) {
    return tagMap[tag] ?? tag;
  }

  static String mapSeries2Kor(String series) {
    return seriesMap[series] ?? series;
  }
}
