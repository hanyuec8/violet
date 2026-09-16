// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter_test/flutter_test.dart';
import 'package:violet/component/hitomi/hitomi_parser.dart';
import 'package:violet/database/query.dart';
import 'package:violet/pages/segment/filter_page_controller.dart';

void main() {
  test('Test Filter Simple', () async {
    var filter = FilterController();
    filter.tagStates = {'male|shota': true};

    final sampleQuery = [
      QueryResult(result: {'Tags': '|male:shota|'}),
      QueryResult(result: {'Tags': '|female:sole female|'}),
    ];

    expect(filter.applyFilter(sampleQuery).first.tags(), '|male:shota|');
  });

  test('HitomiParser galleryblock tags parse and normalize', () async {
    const html = '''
<div class="dj">
<a href="/doujinshi/sample-4185588.html"><img data-src="//tn.gold-usergeneratedcontent.net/webpbigtn/2/20/sample.webp"></a>
<h1>Sample Work</h1>
<div class="artist-list"><ul><li><a href="/artist/nishi-all.html">nishi</a></li></ul></div>
<div class="dj-content">
<table class="dj-desc">
<tr><td>Series</td><td class="series-list">Sample Series</td></tr>
<tr><td>Type</td><td><a href="/type/doujinshi-all.html">doujinshi</a></td></tr>
<tr><td>Language</td><td><a href="/index-korean.html">한국어</a></td></tr>
<tr><td>Tags</td><td class="relatedtags"><ul>
<li><a href="/tag/female%3Aamputee-all.html">amputee ♀</a></li>
<li><a href="/tag/male%3Aamputee-all.html">amputee ♂</a></li>
<li><a href="/tag/digital-all.html">digital</a></li>
</ul></td></tr>
</table>
</div>
</div>
''';
    final parsed = await HitomiParser.parseGalleryBlock(html);
    expect(parsed['Tags'], isNotNull);
    expect(parsed['Tags'], contains('female:amputee'));
    expect(parsed['Tags'], contains('male:amputee'));
    expect(parsed['Tags'], contains('digital'));
    expect(parsed['Language'], 'korean');
    expect(parsed['Type'], 'doujinshi');
  });
}
