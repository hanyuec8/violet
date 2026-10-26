// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:violet/component/index.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/log/log.dart';
import 'package:violet/pages/common/toast.dart';
import 'package:violet/pages/settings/settings_widgets.dart';
import 'package:violet/pages/settings/tag_rebuild_page.dart';
import 'package:violet/pages/settings/tag_selector.dart';
import 'package:violet/settings/settings.dart';

List<Widget> buildSearchGroup(BuildContext context, VoidCallback onReload) {
  return [
    SettingGroupName(name: Translations.instance!.trans('search')),
    buildSettingItems([
      InkWell(
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8.0),
            topRight: Radius.circular(8.0),
          ),
        ),
        child: ListTile(
          leading: Icon(
            MdiIcons.translate,
            color: Settings.majorColor.value,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('기본 검색 언어 설정'),
              Text(
                '현재 언어: ${_getLanguageName(Settings.includeTags.value)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          trailing: const Icon(Icons.keyboard_arrow_right),
        ),
        onTap: () async {
          await _showLanguageSelectorAndRebuild(context, onReload);
        },
      ),
      ListTile(
        leading: Icon(MdiIcons.tagOff, color: Settings.majorColor.value),
        title: Text(Translations.instance!.trans('excludetag')),
        trailing: const Icon(Icons.keyboard_arrow_right),
        onTap: () async {
          final vv = await showDialog<(int, String)?>(
            context: context,
            builder: (BuildContext context) =>
                const TagSelectorDialog(what: 'exclude'),
          );

          if (vv?.$1 == 1) {
            Settings.excludeTags.setValue(vv!.$2.split(' ').toList());
            onReload();
          }
        },
      ),
      InkWell(
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(8.0),
            bottomRight: Radius.circular(8.0),
          ),
        ),
        child: ListTile(
          leading: CachedNetworkImage(
            imageUrl: 'https://e-hentai.org/favicon.ico',
            width: 25,
          ),
          title: const Text('Search Categories'),
            trailing: const Icon(Icons.keyboard_arrow_right),
          ),
          onTap: () async {
            var cats = Settings.searchCategory.value;

            var catsController = TextEditingController(text: '$cats');

            getButton(String name, int cat) {
              return CategoryButton(
                name: name,
                controller: catsController,
                cat: cat,
              );
            }

            final doujinshiButton = getButton('Doujinshi', 1);
            final mangaButton = getButton('Manga', 2);
            final artistcgButton = getButton('Artist CG', 3);
            final gamecgButton = getButton('Game CG', 4);
            final westernButton = getButton('Western', 9);
            final nonhButton = getButton('Non-H', 8);
            final imagesetButton = getButton('Image Set', 5);
            final cosplayButton = getButton('Cosplay', 6);
            final asianpornButton = getButton('Asian Porn', 7);
            final miscButton = getButton('Misc', 0);

            Widget okButton = TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Settings.majorColor.value,
              ),
              child: Text(Translations.instance!.trans('ok')),
              onPressed: () {
                try {
                  cats = int.parse(catsController.text);
                  Settings.searchCategory.setValue(cats);
                } catch (e, st) {
                  Logger.error(
                    '[Search Categories] $e\n'
                    '$st',
                  );
                }
                Navigator.pop(context);
              },
            );
            Widget cancelButton = TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Settings.majorColor.value,
              ),
              child: Text(Translations.instance!.trans('cancel')),
              onPressed: () {
                Navigator.pop(context);
              },
            );
            await showDialog(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                actions: [okButton, cancelButton],
                title: const Text('E-Hentai Categories'),
                contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Text('f_cats: '),
                      ...[
                        TextField(controller: catsController, readOnly: true),
                        doujinshiButton,
                        mangaButton,
                        artistcgButton,
                        gamecgButton,
                        westernButton,
                        nonhButton,
                        imagesetButton,
                        cosplayButton,
                        asianpornButton,
                        miscButton,
                      ].map((e) => Row(children: [Expanded(child: e)])),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
    ]),
  ];
}

String _getLanguageName(String includeTags) {
  final val = includeTags.toLowerCase().trim();
  if (val.isEmpty || val == 'all') return '전체 (언어 필터 없음)';

  final matched = <String>[];
  if (val.contains('korean')) matched.add('한국어');
  if (val.contains('japanese')) matched.add('일본어');
  if (val.contains('english')) matched.add('영어');
  if (val.contains('chinese')) matched.add('중국어');

  if (matched.isNotEmpty) {
    return matched.join(', ');
  }
  return val;
}

Future<void> _showLanguageSelectorAndRebuild(
  BuildContext context,
  VoidCallback onReload,
) async {
  final availableLanguages = [
    ('🇰🇷 한국어 (Korean)', 'korean'),
    ('🇯🇵 일본어 (Japanese)', 'japanese'),
    ('🇺🇸 영어 (English)', 'english'),
    ('🇨🇳 중국어 (Chinese)', 'chinese'),
  ];

  final currentInclude = Settings.includeTags.value.toLowerCase();
  final selectedLangs = <String>{};
  for (var lang in availableLanguages) {
    if (currentInclude.contains(lang.$2)) {
      selectedLangs.add(lang.$2);
    }
  }

  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.language, size: 24),
                SizedBox(width: 8),
                Text('기본 검색 언어 설정'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '원하는 언어를 복수 선택할 수 있습니다.\n설정 시 자동으로 태그 리빌딩이 진행됩니다.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  ...availableLanguages.map((item) {
                    final isChecked = selectedLangs.contains(item.$2);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.$1,
                        style: TextStyle(
                          fontWeight:
                              isChecked ? FontWeight.bold : FontWeight.normal,
                          color: isChecked ? Settings.majorColor.value : null,
                        ),
                      ),
                      value: isChecked,
                      activeColor: Settings.majorColor.value,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            selectedLangs.add(item.$2);
                          } else {
                            selectedLangs.remove(item.$2);
                          }
                        });
                      },
                    );
                  }),
                  const Divider(height: 16),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.select_all, size: 18),
                        label: const Text('전체 언어'),
                        style: TextButton.styleFrom(
                          foregroundColor: Settings.majorColor.value,
                        ),
                        onPressed: () {
                          setState(() {
                            selectedLangs.clear();
                          });
                        },
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('직접 입력'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey.shade600,
                        ),
                        onPressed: () {
                          Navigator.pop(context, '__custom__');
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(
                  Translations.instance!.trans('cancel'),
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Settings.majorColor.value,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  if (selectedLangs.isEmpty) {
                    Navigator.pop(context, '');
                  } else if (selectedLangs.length == 1) {
                    Navigator.pop(context, '(lang:${selectedLangs.first})');
                  } else {
                    final query =
                        '(${selectedLangs.map((e) => 'lang:$e').join(' or ')})';
                    Navigator.pop(context, query);
                  }
                },
                child: const Text('저장 및 리빌딩'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result == null) return;

  if (result == '__custom__') {
    if (!context.mounted) return;
    final vv = await showDialog(
      context: context,
      builder: (BuildContext context) =>
          const TagSelectorDialog(what: 'include'),
    );

    if (vv != null && vv.$1 == 1) {
      await Settings.includeTags.setValue(vv.$2);
      onReload();
    }
    return;
  }

  // 언어 태그 저장
  await Settings.includeTags.setValue(result);

  if (!context.mounted) return;

  // 태그 리빌딩 자동 실행
  await showDialog(
    context: context,
    builder: (BuildContext context) => const TagRebuildPage(),
  );

  await HentaiIndex.init();
  onReload();

  final langDisplay = _getLanguageName(result);
  showToast(
    level: ToastLevel.check,
    message: '기본 언어 ($langDisplay) 설정 및 태그 리빌딩 완료',
  );
}
