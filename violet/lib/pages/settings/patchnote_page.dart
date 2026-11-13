// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/pages/settings/patchnote_data.dart';

export 'package:violet/pages/settings/patchnote_data.dart';

class PatchNotePage extends StatefulWidget {
  const PatchNotePage({super.key});

  @override
  State<PatchNotePage> createState() => _PatchNotePageState();
}

class _PatchNotePageState extends State<PatchNotePage> {
  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final statusBarHeight = mediaQuery.padding.top;

    return Scaffold(
      body: Padding(
        padding: EdgeInsets.only(
          top: statusBarHeight + 16,
          bottom: mediaQuery.padding.bottom,
        ),
        child: Column(
          children: [
            const Text(
              'Patch Note',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(8),
                // addAutomaticKeepAlives: false,
                itemBuilder: (c, i) {
                  final ii = patches[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 12.0,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.0),
                      color: i == 0
                          ? Colors.greenAccent.withValues(alpha: 0.8)
                          : ii.isMajor
                              ? Colors.lightBlueAccent.withValues(alpha: 0.8)
                              : ii.isMinor
                                  ? Colors.orange.withValues(alpha: 0.8)
                                  : Colors.redAccent.withValues(alpha: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              ii.isMajor
                                  ? MdiIcons.chevronTripleUp
                                  : ii.isMinor
                                      ? MdiIcons.chevronDoubleUp
                                      : MdiIcons.trendingUp,
                            ),
                            const SizedBox(width: 12.0),
                            Text(
                              ii.version,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${ii.dateTime.year}.${ii.dateTime.month}.${ii.dateTime.day}',
                                ),
                              ),
                            ),
                            // ii.detail != null
                            //     ? Expanded(
                            //         child: Align(
                            //           alignment: Alignment.centerRight,
                            //           child: SizedBox(
                            //             height: 18.0,
                            //             width: 18.0,
                            //             child: IconButton(
                            //               padding: EdgeInsets.zero,
                            //               icon: Icon(
                            //                 Icons.keyboard_arrow_right,
                            //                 size: 24,
                            //               ),
                            //               onPressed: () async {
                            //                 await showOkDialog(
                            //                     context, ii.detail, 'Detail');
                            //               },
                            //             ),
                            //           ),
                            //         ),
                            //       )
                            //     : Container(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final isKorean = Translations
                                    .instance?.locale.languageCode ==
                                'ko';
                            final displayContents = (isKorean &&
                                    ii.contentsKorean != null &&
                                    ii.contentsKorean!.isNotEmpty)
                                ? ii.contentsKorean!
                                : ii.contents;
                            return Text('* ${displayContents.join('\n* ')}');
                          },
                        ),
                      ],
                    ),
                  );
                },
                itemCount: patches.length,
                separatorBuilder: (context, index) {
                  // return Divider(
                  //   height: 2,
                  // );

                  return const SizedBox(height: 8);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
