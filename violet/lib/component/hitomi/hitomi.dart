// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:violet/script/script_manager.dart';

class ImageList {
  final List<String> urls;
  final List<String> bigThumbnails;
  final List<String>? smallThumbnails;

  const ImageList({
    required this.urls,
    required this.bigThumbnails,
    this.smallThumbnails,
  });
}

class HitomiManager {
  // [Image List], [Big Thumbnail List (Perhaps only two are valid.)], [Small Thubmnail List]
  static Future<ImageList> getImageList(String id) async {
    final result = await ScriptManager.runHitomiGetImageList(int.parse(id));
    if (result != null) return result;
    return const ImageList(urls: [], bigThumbnails: []);
  }
}
