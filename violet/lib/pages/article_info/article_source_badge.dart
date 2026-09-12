// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:violet/model/article_info.dart';

class ArticleSourceBadge extends StatefulWidget {
  final ArticleInfo data;

  const ArticleSourceBadge({super.key, required this.data});

  @override
  State<ArticleSourceBadge> createState() => _ArticleSourceBadgeState();
}

class _ArticleSourceBadgeState extends State<ArticleSourceBadge> {
  late String _source;
  bool _isCommon = false;
  bool _isPupilOnly = false;
  bool _hasEHash = false;
  bool _hasHitomi = false;

  @override
  void initState() {
    super.initState();
    _extractFlags();
  }

  @override
  void didUpdateWidget(covariant ArticleSourceBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.queryResult.id() != widget.data.queryResult.id()) {
      _extractFlags();
    }
  }

  void _extractFlags() {
    final result = widget.data.queryResult.result;
    _source = (result['source'] ?? '').toString();
    _isCommon = result['is_common'] == true || _source == 'common';
    _isPupilOnly = result['is_pupil_only'] == true || _source == 'pupil_only';
    _hasEHash = result['EHash'] != null;
    _hasHitomi = result['ExistOnHitomi'] == 1 || _source == 'pupil' || _isPupilOnly;

    // Pupil 단독으로 명시된 작품은 공통으로 오판되지 않도록 보호
    if (_isPupilOnly) {
      _isCommon = false;
      _hasEHash = false;
    } else if (_isCommon || (_hasEHash && _hasHitomi)) {
      _isCommon = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    String badgeLabel;
    IconData badgeIcon;

    if (_isPupilOnly) {
      badgeColor = Colors.deepOrange;
      badgeLabel = 'Pupil 방식 (단독)';
      badgeIcon = MdiIcons.eyeOutline;
    } else if (_isCommon || (_hasHitomi && _hasEHash)) {
      badgeColor = Colors.teal;
      badgeLabel = 'Violet & Pupil 공통';
      badgeIcon = MdiIcons.swapHorizontalCircleOutline;
    } else if (_hasHitomi && !_hasEHash) {
      badgeColor = Colors.deepOrange;
      badgeLabel = 'Pupil 방식 (단독)';
      badgeIcon = MdiIcons.eyeOutline;
    } else {
      badgeColor = Colors.deepPurple;
      badgeLabel = 'Violet 방식 (Web)';
      badgeIcon = MdiIcons.web;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 16, color: badgeColor),
          const SizedBox(width: 8),
          Text(
            badgeLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }
}
