// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:mdi/mdi.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/style/palette.dart';

class SettingGroupDivider extends StatelessWidget {
  const SettingGroupDivider({super.key});

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

class SettingGroupName extends StatelessWidget {
  final String name;

  const SettingGroupName({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            name,
            style: TextStyle(
              color: Settings.themeWhat.value ? Colors.white : Colors.black87,
              fontSize: 24.0,
              fontFamily: 'Calibre-Semibold',
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

Widget buildSettingItems(List<Widget> items) {
  final itemsWithDividers = items
      .map((e) => [e, SettingGroupDivider(key: GlobalKey())])
      .expand((e) => e)
      .take(items.length * 2 - 1)
      .toList();

  return Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    width: double.infinity,
    decoration: !Settings.themeFlat.value
        ? BoxDecoration(
            color: Settings.themeWhat.value ? Colors.black26 : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            boxShadow: [
              BoxShadow(
                color: Settings.themeWhat.value
                    ? Colors.black26
                    : Colors.grey.withOpacity(0.1),
                spreadRadius: Settings.themeWhat.value ? 0 : 5,
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          )
        : null,
    color: !Settings.themeFlat.value
        ? null
        : Settings.themeWhat.value
        ? Colors.black26
        : Colors.white,
    child: !Settings.themeFlat.value
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Material(
              color: Settings.themeWhat.value
                  ? Settings.themeBlack.value
                        ? Palette.blackThemeBackground
                        : Colors.black38
                  : Colors.white,
              child: Column(children: itemsWithDividers),
            ),
          )
        : Column(children: itemsWithDividers),
  );
}

class CategoryButton extends StatefulWidget {
  final String name;
  final TextEditingController controller;
  final int cat;

  const CategoryButton({
    super.key,
    required this.name,
    required this.controller,
    required this.cat,
  });

  @override
  State<CategoryButton> createState() => _CategoryButtonState();
}

class _CategoryButtonState extends State<CategoryButton> {
  bool stat = false;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      child: ListTile(
        leading: Icon(Mdi.compassOutline, color: Settings.majorColor.value),
        title: Text(widget.name),
        trailing: Switch(
          value: (stat =
              (int.parse(widget.controller.text) & (1 << widget.cat)) == 0),
          onChanged: (newValue) async {
            widget.controller.text =
                ((int.parse(widget.controller.text) ^ (1 << widget.cat))
                    .toString());
            final newStat =
                int.parse(widget.controller.text) & (1 << widget.cat) == 0;
            setState(() {
              stat = newStat;
            });
          },
          activeTrackColor: Settings.majorColor.value,
          activeColor: Settings.majorAccentColor.value,
        ),
      ),
      onTap: () async {
        widget.controller.text =
            ((int.parse(widget.controller.text) ^ (1 << widget.cat))
                .toString());
        final newStat =
            int.parse(widget.controller.text) & (1 << widget.cat) == 0;
        setState(() {
          stat = newStat;
        });
      },
    );
  }
}
