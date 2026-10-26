// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:violet/component/hitomi/hybrid_loader.dart';
import 'package:violet/database/query.dart';
import 'package:violet/database/user/record.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/log/log.dart';
import 'package:violet/model/article_list_item.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/common/utils.dart';
import 'package:violet/pages/segment/card_panel.dart';
import 'package:violet/settings/settings.dart';
import 'package:violet/widgets/article_item/article_list_item_widget.dart';

class RecordArticleItem {
  final ArticleReadLog readLog;
  final QueryResult? queryResult;

  const RecordArticleItem({required this.readLog, this.queryResult});

  bool get isNotFound => queryResult == null;
}

class RecordViewPage extends StatefulWidget {
  const RecordViewPage({super.key});

  @override
  State<RecordViewPage> createState() => _RecordViewPageState();
}

class _RecordViewPageState extends State<RecordViewPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<RecordArticleItem> _items = [];
  List<QueryResult> _usableTabList = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  bool _isIdOnly(QueryResult qr) {
    return (qr.result.keys.length == 1 && qr.result.containsKey('Id')) ||
        (qr.tags() == null && qr.artists() == null && qr.title() == null);
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await User.getInstance();
      final logs = await user.getUserLog();

      final seen = HashSet<String>();
      final distinctLogs = <ArticleReadLog>[];
      for (final log in logs) {
        if (seen.add(log.articleId())) {
          distinctLogs.add(log);
        }
      }

      if (distinctLogs.isEmpty) {
        if (mounted) {
          setState(() {
            _items = [];
            _usableTabList = [];
            _isLoading = false;
          });
        }
        return;
      }

      final intIds = distinctLogs
          .map((e) => int.tryParse(e.articleId()))
          .whereType<int>()
          .toList();

      final resultMap = <int, QueryResult>{};

      // 1. 로컬 DB 조회
      if (intIds.isNotEmpty) {
        try {
          final localResults = await QueryManager.queryIds(intIds);
          for (final qr in localResults) {
            resultMap[qr.id()] = qr;
          }
        } catch (e, st) {
          Logger.error('[RecordViewPage-LocalQuery] E: $e\n$st');
        }
      }

      // 2. ArticleCache (디스크/세션 캐시) 일괄 조회
      final missingIds = intIds
          .where((id) => !resultMap.containsKey(id) || _isIdOnly(resultMap[id]!))
          .toList();
      if (missingIds.isNotEmpty) {
        try {
          final cachedBatch =
              await HybridLoader.getCachedMetadataBatch(missingIds);
          for (final entry in cachedBatch.entries) {
            if (!_isIdOnly(entry.value)) {
              resultMap[entry.key] = entry.value;
            }
          }
        } catch (e, st) {
          Logger.error('[RecordViewPage-CacheBatch] E: $e\n$st');
        }
      }

      // 3. 여전히 누락된 작품 온라인 조회 (경량, 최대 20개, 2초 타임아웃)
      final stillMissing = intIds
          .where((id) => !resultMap.containsKey(id) || _isIdOnly(resultMap[id]!))
          .take(20)
          .toList();
      if (stillMissing.isNotEmpty && !Settings.recordSearchDatabaseOnly.value) {
        await Future.wait(
          stillMissing.map((id) async {
            try {
              final res = await HybridLoader.idQueryHitomiFast(id)
                  .timeout(const Duration(seconds: 2));
              if (!_isIdOnly(res)) {
                resultMap[id] = res;
              }
            } catch (_) {}
          }),
        );
      }

      // 4. 결과 매핑
      final items = distinctLogs.map((readLog) {
        final id = int.tryParse(readLog.articleId());
        final qr = id != null ? resultMap[id] : null;
        return RecordArticleItem(
          readLog: readLog,
          queryResult: qr,
        );
      }).toList();

      final usableTabList = items
          .map((e) => e.queryResult)
          .whereType<QueryResult>()
          .where((e) => !_isIdOnly(e))
          .toList();

      if (mounted) {
        setState(() {
          _items = items;
          _usableTabList = usableTabList;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      Logger.error('[RecordViewPage-Load] E: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearAllRecords() async {
    if (!await showYesNoDialog(
      context,
      '열람 기록을 모두 삭제할까요?',
      Translations.instance!.trans('readrecord'),
    )) {
      return;
    }

    final user = await User.getInstance();
    await user.clearUserLog();
    await _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return CardPanel.build(
      context,
      enableBackgroundColor: true,
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Translations.instance!.trans('readrecord'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!_isLoading && _items.isNotEmpty)
                  Text(
                    '총 ${_items.length}개 작품',
                    style: TextStyle(
                      fontSize: 12,
                      color: Settings.themeWhat.value
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: _isLoading ? null : _loadRecords,
          ),
          if (_items.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') {
                  _clearAllRecords();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                      SizedBox(width: 8),
                      Text(
                        '기록 모두 삭제',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              const Text(
                '열람 기록을 불러오지 못했습니다.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRecords,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              '아직 열람한 작품 기록이 없습니다.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final windowWidth = MediaQuery.of(context).size.width;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final columnCount = isLandscape ? 4 : 3;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3 / 4,
      ),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final e = _items[index];
        final itemWidth =
            (windowWidth - 16 - 8 * (columnCount - 1)) / columnCount;
        return Padding(
          key: Key('record/${e.readLog.articleId()}_$index'),
          padding: EdgeInsets.zero,
          child: e.isNotFound
              ? RecordArticleNotFoundItem(
                  articleId: e.readLog.articleId(),
                  width: itemWidth,
                )
              : Provider<ArticleListItem>.value(
                  value: ArticleListItem.fromArticleListItem(
                    queryResult: e.queryResult!,
                    addBottomPadding: false,
                    showDetail: false,
                    width: itemWidth,
                    thumbnailTag: 'record_${e.readLog.articleId()}_$index',
                    usableTabList: _usableTabList,
                  ),
                  child: const ArticleListItemWidget(),
                ),
        );
      },
    );
  }
}

class RecordArticleNotFoundItem extends StatelessWidget {
  final String articleId;
  final double width;

  const RecordArticleNotFoundItem({
    super.key,
    required this.articleId,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      onTap: () {
        showArticleInfoNotFound(
          context,
          int.tryParse(articleId) ?? 0,
          title: Translations.instance!.trans('articlenotfound'),
        );
      },
      child: SizedBox(
        width: width,
        height: width * 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.18),
                spreadRadius: 3,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 36,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 6),
              Text(
                articleId,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
