// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/settings/settings.dart';

class SearchPageModifyPage extends StatefulWidget {
  final int curPage;
  final int maxPage;

  const SearchPageModifyPage({
    super.key,
    required this.curPage,
    required this.maxPage,
  });

  @override
  State<SearchPageModifyPage> createState() => _SearchPageModifyPageState();
}

class _SearchPageModifyPageState extends State<SearchPageModifyPage> {
  late final TextEditingController _pageController;

  @override
  void initState() {
    super.initState();

    _pageController = TextEditingController(text: widget.curPage.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Item Jump'),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: [
              Text('${Translations.instance!.trans('position')}: '),
              Expanded(
                child: TextField(
                  controller: _pageController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ], // Only numbers can be entered
                ),
              ),
              Text(
                ' / ${widget.maxPage > 0 ? widget.maxPage : '∞'}',
              ),
            ],
          ),
          if (Settings.lastSearchArticleId.value > 0) ...[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Settings.themeWhat.value
                    ? Colors.grey.shade100
                    : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Settings.majorColor.value.withOpacity(0.5),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bookmark_added,
                        size: 16,
                        color: Settings.majorColor.value,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '마지막 본 작품 (No. ${Settings.lastSearchArticleId.value})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Settings.majorColor.value,
                          ),
                        ),
                      ),
                      if (Settings.lastSearchIsPupil.value)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Pupil',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (Settings.lastSearchArticleTitle.value.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      Settings.lastSearchArticleTitle.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.near_me, size: 14),
                      label: Text(
                        '이 작품 위치로 이동 (당시 ${Settings.lastSearchPosition.value}번)',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Settings.majorColor.value,
                        side: BorderSide(color: Settings.majorColor.value),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () {
                        Navigator.pop(context, [2]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ] else if (Settings.lastSearchPosition.value > 0 &&
              Settings.lastSearchPosition.value != widget.curPage) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.history, size: 16),
                label: Text('이어서 보기 (${Settings.lastSearchPosition.value}번)'),
                onPressed: () {
                  setState(() {
                    _pageController.text =
                        Settings.lastSearchPosition.value.toString();
                    _pageController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _pageController.text.length),
                    );
                  });
                },
              ),
            ),
          ],
          Container(height: 16),
          Row(
            children: <Widget>[
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Settings.majorColor.value,
                ),
                child: Text(Translations.instance!.trans('ok')),
                onPressed: () {
                  if (_pageController.text.trim().isEmpty) {
                    Navigator.pop(context, [1, 0]);
                    return;
                  }
                  final target = int.tryParse(_pageController.text.trim()) ?? 0;
                  Navigator.pop(context, [1, target]);
                },
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Settings.majorColor.value,
                ),
                child: Text(Translations.instance!.trans('cancel')),
                onPressed: () {
                  Navigator.pop(context, [0]);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
