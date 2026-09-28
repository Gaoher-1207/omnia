import 'package:flutter/material.dart';

/// A deliberately small Markdown subset for model text. Unsupported syntax and
/// HTML stay literal text; nothing here executes or navigates.
class AssistantRichText extends StatelessWidget {
  const AssistantRichText(this.source, {super.key});
  final String source;

  static final _list = RegExp(r'^(\d+\.|[-*])\s+(.+)$');
  static final _heading = RegExp(r'^#{1,3}\s+(.+)$');

  @override
  Widget build(BuildContext context) {
    final bodyStyle = DefaultTextStyle.of(context).style.copyWith(height: 1.35);
    if (!source.contains('\n') && !_hasMarkup(source)) {
      return Text(source, style: bodyStyle);
    }
    final blocks = <Widget>[];
    final paragraph = <String>[];
    void flush() {
      if (paragraph.isEmpty) return;
      blocks.add(_rich(paragraph.join('\n'), bodyStyle));
      paragraph.clear();
    }

    for (final raw in source.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final heading =
          _heading.firstMatch(line) ??
          (line.startsWith('**') && line.endsWith('**') && line.length > 4
              ? RegExp(r'^\*\*(.+)\*\*$').firstMatch(line)
              : null);
      if (heading != null) {
        flush();
        blocks.add(
          SelectableText(
            heading.group(1)!,
            style: bodyStyle.copyWith(
              fontSize: (bodyStyle.fontSize ?? 14) + 2,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
        continue;
      }
      final entry = _list.firstMatch(line);
      if (entry != null) {
        flush();
        blocks.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  entry.group(1) == '-' || entry.group(1) == '*'
                      ? '•'
                      : entry.group(1)!,
                  style: bodyStyle,
                ),
              ),
              Expanded(child: _rich(entry.group(2)!, bodyStyle)),
            ],
          ),
        );
      } else {
        paragraph.add(line);
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed) ...[
          if (index > 0) const SizedBox(height: 7),
          block,
        ],
      ],
    );
  }

  static bool _hasMarkup(String text) =>
      text.contains('**') ||
      text.contains('__') ||
      text.contains('*') ||
      text.contains('_');

  static Widget _rich(String value, TextStyle style) {
    final spans = <TextSpan>[];
    var plainStart = 0;
    var cursor = 0;
    while (cursor < value.length) {
      final marker = value.startsWith('**', cursor)
          ? '**'
          : value.startsWith('__', cursor)
          ? '__'
          : value[cursor] == '*' || value[cursor] == '_'
          ? value[cursor]
          : null;
      if (marker == null) {
        cursor++;
        continue;
      }
      final close = value.indexOf(marker, cursor + marker.length);
      if (close <= cursor + marker.length) {
        cursor += marker.length;
        continue;
      }
      if (plainStart < cursor) {
        spans.add(TextSpan(text: value.substring(plainStart, cursor)));
      }
      spans.add(
        TextSpan(
          text: value.substring(cursor + marker.length, close),
          style: TextStyle(
            fontWeight: marker.length == 2 ? FontWeight.w800 : null,
            fontStyle: marker.length == 1 ? FontStyle.italic : null,
          ),
        ),
      );
      cursor = close + marker.length;
      plainStart = cursor;
    }
    if (plainStart < value.length) {
      spans.add(TextSpan(text: value.substring(plainStart)));
    }
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}
