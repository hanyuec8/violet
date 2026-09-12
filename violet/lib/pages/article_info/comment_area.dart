// This source code is a part of Project Violet.
// Copyright (C) 2020-2024. violet-team. Licensed under the Apache-2.0 License.

import 'package:expandable/expandable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:violet/component/eh/eh_headers.dart';
import 'package:violet/database/query.dart';
import 'package:violet/locale/locale.dart';
import 'package:violet/other/dialogs.dart';
import 'package:violet/pages/common/utils.dart';
import 'package:violet/settings/settings.dart';

const String urlPattern = r'http';
const String emailPattern = r'\S+@\S+';
const String phonePattern = r'[\d-]{9,}';
final RegExp linkRegExp = RegExp(
  '($urlPattern)|($emailPattern)|($phonePattern)',
  caseSensitive: false,
);

class CommentArea extends StatefulWidget {
  final QueryResult queryResult;

  const CommentArea({super.key, required this.queryResult});

  @override
  State<CommentArea> createState() => _CommentAreaState();
}

class _CommentAreaState extends State<CommentArea> {
  List<(DateTime, String, String)> comments = [];

  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 100)).then((value) async {
      if (widget.queryResult.ehash() == null) {
        return;
      }

      final article = await EHSession.fetchArticle(
        widget.queryResult.id(),
        widget.queryResult.ehash(),
      );
      if (article != null) {
        setState(() {
          comments.addAll(article.comment ?? []);
          comments.sort((x, y) => x.$1.compareTo(y.$1));
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _InfoAreaWidget(queryResult: widget.queryResult, comments: comments);
  }
}

class _InfoAreaWidget extends StatefulWidget {
  final QueryResult queryResult;
  final List<(DateTime, String, String)> comments;

  const _InfoAreaWidget({required this.queryResult, required this.comments});

  @override
  State<_InfoAreaWidget> createState() => _InfoAreaWidgetState();
}

class _InfoAreaWidgetState extends State<_InfoAreaWidget> {
  @override
  Widget build(BuildContext context) {
    return ExpandableNotifier(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: ScrollOnExpand(
          child: ExpandablePanel(
            theme: ExpandableThemeData(
              iconColor: Settings.themeWhat.value ? Colors.white : Colors.grey,
              animationDuration: const Duration(milliseconds: 500),
            ),
            header: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
              child: Text(
                '${Translations.instance!.trans('comment')} (${widget.comments.length})',
              ),
            ),
            expanded: commentArea(context),
            collapsed: Container(),
          ),
        ),
      ),
    );
  }

  Widget commentArea(BuildContext context) {
    if (widget.comments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: Align(
                  child: Text('No Comments', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
          comment(context),
        ],
      );
    } else {
      var children = List<Widget>.from(
        widget.comments.map((e) {
          return InkWell(
            onTap: () async {
              AlertDialog alert = AlertDialog(
                content: SelectableText(e.$3),
              );
              await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return alert;
                },
              );
            },
            onLongPress: () async {
              await Clipboard.setData(ClipboardData(text: e.$3));
              Fluttertoast.showToast(msg: '댓글 내용이 클립보드에 복사되었습니다.');
            },
            splashColor: Colors.white,
            child: ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  Text(e.$2),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(e.$1.toLocal()),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: buildTextWithLinks(e.$3),
            ),
          );
        }),
      );

      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children + [comment(context)],
        ),
      );
    }
  }

  Widget comment(BuildContext context) {
    return InkWell(
      onTap: () async {
        if (widget.queryResult.ehash() == null) {
          await showOkDialog(context, 'Cannot write comment!');
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        var cookie = prefs.getString('eh_cookies');
        if (cookie == null || !cookie.contains('ipb_pass_hash')) {
          if (!context.mounted) return;
          await showOkDialog(context, 'Please, Login First!');
          return;
        }

        TextEditingController text = TextEditingController();
        Widget okButton = TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Settings.majorColor.value,
          ),
          child: Text(Translations.instance!.trans('ok')),
          onPressed: () async {
            if ((await EHSession.postComment(
                  'https://exhentai.org/g/${widget.queryResult.id()}/${widget.queryResult.ehash()}',
                  text.text,
                )).trim() !=
                '') {
              if (!context.mounted) return;
              await showOkDialog(
                context,
                'Too short, or Not a valid session! Try Again!',
              );
              return;
            }
            if (!context.mounted) return;
            Navigator.pop(context, true);
          },
        );
        Widget cancelButton = TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Settings.majorColor.value,
          ),
          child: Text(Translations.instance!.trans('cancel')),
          onPressed: () {
            Navigator.pop(context, false);
          },
        );
        if (!context.mounted) return;
        await showDialog(
          useRootNavigator: false,
          context: context,
          builder: (BuildContext context) => AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            title: const Text('Write Comment'),
            content: TextField(controller: text, autofocus: true),
            actions: [okButton, cancelButton],
          ),
        );
      },
      splashColor: Colors.white,
      child: const ListTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [Text('Write Comment')],
        ),
      ),
    );
  }

  TextSpan buildLinkComponent(String text, String linkToOpen) => TextSpan(
    text: text,
    style: const TextStyle(
      color: Colors.blueAccent,
      decoration: TextDecoration.underline,
    ),
    recognizer: TapGestureRecognizer()
      ..onTap = () {
        openUrl(linkToOpen);
      },
  );

  Future<void> openUrl(String url) async {
    final ehPattern = RegExp(
      r'^(https?://)?e(-|x)hentai.org/g/(?<id>\d+)/(?<hash>\w+)/?$',
    );
    if (ehPattern.stringMatch(url) == url) {
      var match = ehPattern.allMatches(url);
      var id = match.first.namedGroup('id')!.trim();
      showArticleInfoById(context, int.parse(id));
    } else if (await canLaunchUrlString(url)) {
      await launchUrlString(url);
    }
  }

  List<InlineSpan> linkify(String text) {
    final List<InlineSpan> list = <InlineSpan>[];
    final RegExpMatch? match = RegExp(
      r'(https?://.*?)([\<"\n\r ]|$)',
    ).firstMatch(text);
    if (match == null) {
      list.add(TextSpan(text: text));
      return list;
    }

    if (match.start > 0) {
      list.add(TextSpan(text: text.substring(0, match.start)));
    }

    final String linkText = match.group(1)!;
    if (linkText.contains(RegExp(urlPattern, caseSensitive: false))) {
      list.add(buildLinkComponent(linkText, linkText));
    } else if (linkText.contains(RegExp(emailPattern, caseSensitive: false))) {
      list.add(buildLinkComponent(linkText, 'mailto:$linkText'));
    } else if (linkText.contains(RegExp(phonePattern, caseSensitive: false))) {
      list.add(buildLinkComponent(linkText, 'tel:$linkText'));
    } else {
      throw 'Unexpected match: $linkText';
    }

    list.addAll(linkify(text.substring(match.start + linkText.length)));

    return list;
  }

  Text buildTextWithLinks(String textToLink) =>
      Text.rich(TextSpan(children: linkify(textToLink)));
}
