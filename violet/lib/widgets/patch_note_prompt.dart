// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/pages/settings/patchnote_page.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/style/palette.dart';
import 'package:violet/version/update_sync.dart';

class PatchNotePrompt extends StatefulWidget {
  const PatchNotePrompt({super.key});

  @override
  State<PatchNotePrompt> createState() => _PatchNotePromptState();
}

class _PatchNotePromptState extends State<PatchNotePrompt> {
  bool _doNotShowAgain = true; // 기본 체크됨

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = patches.isNotEmpty ? patches.first : null;
    final IconData headerIcon = latest == null
        ? Icons.new_releases
        : latest.isMajor
        ? MdiIcons.chevronTripleUp
        : latest.isMinor
        ? MdiIcons.chevronDoubleUp
        : MdiIcons.trendingUp;

    final isDark = Settings.themeWhat.value;
    final Color dialogBg = isDark
        ? (Settings.themeBlack.value ? Palette.blackThemeBackground : const Color(0xFF282828))
        : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color dividerColor = isDark ? Colors.white12 : Colors.black12;

    final Color headerBaseColor = Settings.majorColor.value;
    final Color onHeaderColor =
        ThemeData.estimateBrightnessForColor(headerBaseColor) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final Color major = Settings.majorColor.value;
    final Color onMajor =
        ThemeData.estimateBrightnessForColor(major) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: dialogBg,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      headerBaseColor.withValues(alpha: 0.95),
                      headerBaseColor.withValues(alpha: 0.75),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(headerIcon, color: onHeaderColor),
                    const SizedBox(width: 8),
                    Text(
                      Translations.instance!.trans('patchnote'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: onHeaderColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LatestPatchSummaryCard(),
                    const SizedBox(height: 12),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() {
                          _doNotShowAgain = !_doNotShowAgain;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _doNotShowAgain,
                              activeColor: major,
                              checkColor: onMajor,
                              onChanged: (v) {
                                setState(() {
                                  _doNotShowAgain = v ?? true;
                                });
                              },
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                Translations.instance!.trans('donotshowagain'),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: dividerColor),
              // Footer buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? Colors.grey.shade300 : major,
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PatchNotePage(),
                          ),
                        );
                      },
                      child: Text(Translations.instance!.trans('more')),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: major,
                        foregroundColor: onMajor,
                      ),
                      onPressed: () async {
                        // Save per-version shown mark only when checked
                        if (_doNotShowAgain) {
                          await Settings.lastPatchNoteShownVersion.setValue(
                            UpdateSyncManager.currentVersion,
                          );
                        }
                        // Per-version gating only: no global hide flag
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: Text(Translations.instance!.trans('ok')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LatestPatchSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (patches.isEmpty) {
      return const Text('표시할 패치 노트가 없습니다.');
    }
    final latest = patches.first;
    final isDark = Settings.themeWhat.value;
    final cardBg = isDark
        ? (Settings.themeBlack.value ? const Color(0xFF1E1E1E) : const Color(0xFF333333))
        : const Color(0xFFF3F4F6);
    final borderColor = isDark ? Colors.white24 : Colors.black12;
    final titleColor = isDark ? Colors.white : Colors.black87;
    final dateColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final bodyColor = isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87;

    final isKorean = Translations.instance?.locale.languageCode == 'ko';
    final displayContents = (isKorean &&
            latest.contentsKorean != null &&
            latest.contentsKorean!.isNotEmpty)
        ? latest.contentsKorean!
        : latest.contents;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.new_releases, color: Settings.majorColor.value, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  latest.version,
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${latest.dateTime.year}.${latest.dateTime.month}.${latest.dateTime.day}',
                style: TextStyle(
                  color: dateColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...displayContents.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ',
                    style: TextStyle(
                      color: Settings.majorColor.value,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e,
                      style: TextStyle(
                        color: bodyColor,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showPatchNotePromptIfNeeded(BuildContext context) async {
  // Show only when app version changed
  final String current = UpdateSyncManager.currentVersion;
  final String lastShown = Settings.lastPatchNoteShownVersion.value;
  final bool versionChanged = lastShown != current;

  if (!versionChanged) return;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PatchNotePrompt(),
  );
}
