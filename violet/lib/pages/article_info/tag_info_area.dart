// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:violet/component/hitomi/tag_translate.dart';
import 'package:violet/context/modal_bottom_sheet_context.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/bookmark.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/artist_info/artist_info_page.dart';
import 'package:violet/pages/common/toast.dart';
import 'package:violet/pages/search/search_page.dart';
import 'package:violet/pages/segment/platform_navigator.dart';
import 'package:violet/settings/settings.dart';

class DividerWidget extends StatelessWidget {
  const DividerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      width: double.infinity,
      height: 1.0,
      color: Settings.themeWhat.value
          ? Colors.grey.shade600
          : Colors.grey.shade400,
    );
  }
}

class TagInfoAreaWidget extends StatelessWidget {
  final QueryResult queryResult;

  const TagInfoAreaWidget({super.key, required this.queryResult});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: [
        MultiChipWidget(
          Translations.instance!.trans('tags'),
          queryResult.tagList(),
        ),
        SingleChipWidget(
          queryResult.language(),
          Translations.instance!.trans('language').split(' ')[0].trim(),
          'language',
        ),
        MultiChipWidget(
          Translations.instance!.trans('artist'),
          queryResult.artists() != null
              ? (queryResult.artists() as String)
                    .split('|')
                    .where((element) => element != '')
                    .map((e) => ('artist', e))
                    .toList()
              : [],
        ),
        MultiChipWidget(
          Translations.instance!.trans('group'),
          queryResult.groups() != null
              ? (queryResult.groups() as String)
                    .split('|')
                    .where((element) => element != '')
                    .map((e) => ('group', e))
                    .toList()
              : [],
        ),
        MultiChipWidget(
          Translations.instance!.trans('series'),
          queryResult.series() != null
              ? (queryResult.series() as String)
                    .split('|')
                    .where((element) => element != '')
                    .map((e) => ('series', e))
                    .toList()
              : [],
        ),
        MultiChipWidget(
          Translations.instance!.trans('character'),
          queryResult.characters() != null
              ? (queryResult.characters() as String)
                    .split('|')
                    .where((element) => element != '')
                    .map((e) => ('character', e))
                    .toList()
              : [],
        ),
        SingleChipWidget(
          queryResult.type(),
          Translations.instance!.trans('type'),
          'type',
        ),
        SingleChipWidget(
          queryResult.uploader(),
          Translations.instance!.trans('uploader'),
          'uploader',
        ),
        SingleChipWidget(
          queryResult.id().toString(),
          Translations.instance!.trans('id'),
          'id',
        ),
        SingleChipWidget(
          queryResult.classname(),
          Translations.instance!.trans('class'),
          'class',
        ),
        Container(height: 10),
      ],
    );
  }

  Widget multipleChip(dynamic target, String name, List<Widget> wrap) {
    if (target == null) return Container();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Text(
            '    $name: ',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: Wrap(spacing: 1.0, runSpacing: -12.0, children: wrap)),
      ],
    );
  }
}

class SingleChipWidget extends StatelessWidget {
  final String? target;
  final String name;
  final String raw;

  const SingleChipWidget(this.target, this.name, this.raw, {super.key});

  @override
  Widget build(BuildContext context) {
    if (target == null) return Container();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Text(
            '    $name: ',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Wrap(
          children: <Widget>[TagChip(group: raw.toLowerCase(), name: target!)],
        ),
      ],
    );
  }
}

class MultiChipWidget extends StatelessWidget {
  final List<(String, String)> groupName;
  final String name;

  const MultiChipWidget(this.name, this.groupName, {super.key});

  @override
  Widget build(BuildContext context) {
    if (groupName.isEmpty) return Container();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Text(
            '    $name: ',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 3.0,
            runSpacing: -9.0,
            children: groupName
                .map((x) => TagChip(group: x.$1, name: x.$2))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class TagChip extends StatelessWidget {
  final String name;
  final String group;

  const TagChip({super.key, required this.name, required this.group});

  String normalize(String tag) {
    if (tag == 'groups') return 'group';
    if (tag == 'artists') return 'artist';
    if (tag == 'tags') return 'tag';
    return tag;
  }

  @override
  Widget build(BuildContext context) {
    var tagDisplayed = name;
    Color color = Colors.grey;

    if (Settings.translateTags.value) {
      tagDisplayed = TagTranslate.ofAny(
        tagDisplayed,
      ).split(':').last.split('|').first;
    }

    if (group == 'female') {
      color = Colors.pink.shade400;
    } else if (group == 'male') {
      color = Colors.blue;
    } else if (group == 'prefix') {
      color = Colors.orange;
    } else if (group == 'id') {
      color = Colors.orange;
    }

    var mustHasMorePad = true;
    Widget avatar = Text(
      group[0].toUpperCase(),
      style: const TextStyle(color: Colors.white),
    );

    if (group == 'female') {
      mustHasMorePad = false;
      avatar = const Icon(
        MdiIcons.genderFemale,
        size: 18.0,
        color: Colors.white,
      );
    } else if (group == 'male') {
      mustHasMorePad = false;
      avatar = const Icon(MdiIcons.genderMale, size: 18.0, color: Colors.white);
    } else if (group == 'language') {
      mustHasMorePad = false;
      avatar = const Icon(Icons.language, size: 18.0, color: Colors.white);
    } else if (group == 'artist') {
      mustHasMorePad = false;
      avatar = const Icon(MdiIcons.account, size: 18.0, color: Colors.white);
    } else if (group == 'group') {
      mustHasMorePad = false;
      avatar = const Icon(
        MdiIcons.accountGroup,
        size: 15.0,
        color: Colors.white,
      );
    }

    final fc = GestureDetector(
      child: RawChip(
        labelPadding: const EdgeInsets.all(0.0),
        label: Row(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 2.0 + (mustHasMorePad ? 4.0 : 0),
                right: (mustHasMorePad ? 4.0 : 0),
              ),
              child: avatar,
            ),
            Text(
              ' $tagDisplayed ',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        backgroundColor: color,
        elevation: 6.0,
        padding: const EdgeInsets.all(6.0),
      ),
      onDoubleTap: () async {
        final targetTag = '${normalize(group)}:${name.replaceAll(' ', '_')}';

        CupertinoScaffold? cached;
        if (ModalBottomSheetContext.up() == 0) {
          await CupertinoScaffold.showCupertinoModalBottomSheet(
            context: context,
            builder: (context) {
              cached ??= CupertinoScaffold(
                body: SearchPage(searchKeyWord: targetTag),
              );
              return cached!;
            },
          );
        } else {
          await showCupertinoModalBottomSheet(
            context: context,
            builder: (context) {
              cached ??= CupertinoScaffold(
                body: SearchPage(searchKeyWord: targetTag),
              );
              return cached!;
            },
          );
        }

        ModalBottomSheetContext.down();
      },
      onLongPress: () async {
        final targetTag = '${normalize(group)}:${name.replaceAll(' ', '_')}';
        if (!Settings.excludeTags.value.contains(targetTag)) {
          final yn = await showYesNoDialog(
            context,
            '$targetTag 태그를 제외태그에 추가할까요?',
          );
          if (yn) {
            Settings.excludeTags.value.add(targetTag);
            await Settings.excludeTags.setValue(Settings.excludeTags.value);
            if (context.mounted) {
              await showOkDialog(context, '제외태그에 성공적으로 추가했습니다!');
            }
          }
        } else {
          await showOkDialog(context, '$targetTag 태그는 이미 제외태그에 추가된 항목입니다!');
        }
      },
      onTap: () async {
        final type = ArtistTypeHelper.fromString(group);
        if (type != null && name.toLowerCase() != 'n/a') {
          PlatformNavigator.navigateSlide(
            context,
            ArtistInfoPage(name: name, type: type),
          );
        } else if (group == 'id') {
          Clipboard.setData(ClipboardData(text: name));
          showToast(
            level: ToastLevel.check,
            message: Translations.instance!.trans('copied'),
          );
        }
      },
    );

    return SizedBox(height: 42, child: FittedBox(child: fc));
  }
}
