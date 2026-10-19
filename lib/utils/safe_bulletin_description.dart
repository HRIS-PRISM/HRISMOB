import 'package:flutter/foundation.dart';

/// A display-only portion of a bulletin description.
///
/// The parser never creates HTML, links, images, or executable content. The
/// UI maps these runs directly to Flutter [TextSpan]s.
@immutable
class BulletinDescriptionRun {
  const BulletinDescriptionRun(
    this.text, {
    required this.bold,
    this.italic = false,
    this.underline = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  @override
  bool operator ==(Object other) =>
      other is BulletinDescriptionRun &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(text, bold, italic, underline);
}

/// Converts the small, trusted formatting subset used by bulletin descriptions
/// into inert text runs.
///
/// Only bold, italic, underline, and list markup affects presentation. Break
/// and block tags become line breaks, unsupported tags are removed, and unsafe
/// container elements are discarded together with all of their contents.
List<BulletinDescriptionRun> parseBulletinDescription(String source) {
  final parser = _BulletinDescriptionParser();
  parser.parse(source);
  return parser.finish();
}

class _BulletinDescriptionParser {
  static final RegExp _tag = RegExp(
    r'''^<\s*(/?)\s*([A-Za-z][A-Za-z0-9]*)\b(?:[^>"']|"[^"]*"|'[^']*')*>''',
    caseSensitive: false,
  );
  static final RegExp _unsafePrefix = RegExp(
    r'^<\s*/?\s*(script|style|iframe|object|embed|template)\b',
    caseSensitive: false,
  );
  static final RegExp _malformedTagPrefix = RegExp(r'^</?[A-Za-z]');
  static final RegExp _selfClosing = RegExp(r'/\s*>$');
  static final RegExp _entity = RegExp(
    r'&(#(?:[xX][0-9A-Fa-f]+|[0-9]+)|[A-Za-z][A-Za-z0-9]+);',
  );

  static const Set<String> _unsafeTags = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'template',
  };
  static const Set<String> _paragraphTags = {'p'};
  static const Set<String> _blockTags = {
    'address',
    'article',
    'aside',
    'blockquote',
    'div',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'main',
    'nav',
    'section',
  };
  static const Map<String, String> _namedEntities = {
    'amp': '&',
    'apos': "'",
    'gt': '>',
    'lt': '<',
    'nbsp': '\u00a0',
    'quot': '"',
  };

  final List<_MutableRun> _runs = [];
  final List<String> _unsafeStack = [];
  final List<_InlineStyle> _inlineStyles = [];
  final List<_ListContext> _lists = [];

  void parse(String source) {
    var offset = 0;
    while (offset < source.length) {
      if (source.startsWith('<!--', offset)) {
        final end = source.indexOf('-->', offset + 4);
        if (end < 0) break;
        offset = end + 3;
        continue;
      }

      if (source.codeUnitAt(offset) != 0x3c) {
        final next = source.indexOf('<', offset);
        final end = next < 0 ? source.length : next;
        if (_unsafeStack.isEmpty) {
          _appendText(_decodeEntities(source.substring(offset, end)));
        }
        offset = end;
        continue;
      }

      final remaining = source.substring(offset);
      if (remaining.startsWith('<!') || remaining.startsWith('<?')) {
        final end = remaining.indexOf('>');
        if (end < 0) break;
        offset += end + 1;
        continue;
      }
      final match = _tag.firstMatch(remaining);
      if (match == null) {
        if (_unsafeStack.isNotEmpty || _unsafePrefix.hasMatch(remaining)) {
          // An unclosed unsafe element discards the remainder. Inside an
          // unsafe element, a non-tag '<' is simply ignored with its content.
          if (_unsafePrefix.hasMatch(remaining)) break;
          offset++;
          continue;
        }
        if (_malformedTagPrefix.hasMatch(remaining)) break;
        _appendText('<');
        offset++;
        continue;
      }

      final rawTag = match.group(0)!;
      final closing = match.group(1)!.isNotEmpty;
      final name = match.group(2)!.toLowerCase();
      final selfClosing = _selfClosing.hasMatch(rawTag);
      offset += rawTag.length;

      if (_unsafeStack.isNotEmpty) {
        if (_unsafeTags.contains(name)) {
          if (closing) {
            if (_unsafeStack.last == name) _unsafeStack.removeLast();
          } else if (!selfClosing) {
            _unsafeStack.add(name);
          }
        }
        continue;
      }

      if (_unsafeTags.contains(name)) {
        if (!closing && !selfClosing && name != 'embed') {
          _unsafeStack.add(name);
        }
        continue;
      }
      final inlineStyle = _inlineStyleFor(name);
      if (inlineStyle != null) {
        if (closing) {
          _closeInlineStyle(inlineStyle);
        } else if (!selfClosing) {
          _inlineStyles.add(inlineStyle);
        }
        continue;
      }
      if (name == 'ol' || name == 'ul') {
        if (closing) {
          _closeList(name);
        } else if (!selfClosing) {
          _appendBreak(1);
          _lists.add(_ListContext(ordered: name == 'ol'));
        }
        continue;
      }
      if (name == 'li') {
        if (closing) {
          _appendBreak(1);
        } else if (!selfClosing) {
          _openListItem();
        }
        continue;
      }
      if (name == 'br') {
        if (!closing) _appendBreak(1);
        continue;
      }
      if (_paragraphTags.contains(name)) {
        _appendBreak(2);
        continue;
      }
      if (_blockTags.contains(name)) {
        _appendBreak(1);
      }
      // All other tags are intentionally ignored while their text remains.
    }
  }

  void _appendText(String text) {
    if (text.isEmpty) return;
    final bold = _inlineStyles.contains(_InlineStyle.bold);
    final italic = _inlineStyles.contains(_InlineStyle.italic);
    final underline = _inlineStyles.contains(_InlineStyle.underline);
    if (_runs.isNotEmpty &&
        _runs.last.bold == bold &&
        _runs.last.italic == italic &&
        _runs.last.underline == underline) {
      _runs.last.text += text;
    } else {
      _runs.add(_MutableRun(text, bold, italic, underline));
    }
  }

  void _openListItem() {
    _appendBreak(1);
    if (_lists.isEmpty) return;
    final list = _lists.last;
    final indent = '  ' * (_lists.length - 1).clamp(0, 6);
    final marker = list.ordered ? '${list.nextNumber++}. ' : '• ';
    _appendText('$indent$marker');
  }

  void _closeList(String name) {
    final ordered = name == 'ol';
    final index = _lists.lastIndexWhere((list) => list.ordered == ordered);
    if (index >= 0) {
      _lists.removeRange(index, _lists.length);
    }
    _appendBreak(1);
  }

  void _closeInlineStyle(_InlineStyle style) {
    final index = _inlineStyles.lastIndexOf(style);
    if (index >= 0) _inlineStyles.removeAt(index);
  }

  static _InlineStyle? _inlineStyleFor(String name) => switch (name) {
    'b' || 'strong' => _InlineStyle.bold,
    'i' || 'em' => _InlineStyle.italic,
    'u' => _InlineStyle.underline,
    _ => null,
  };

  void _appendBreak(int count) {
    if (_runs.isEmpty) return;
    final present = _trailingNewlineCount();
    if (present < count) {
      _appendText(List.filled(count - present, '\n').join());
    }
  }

  int _trailingNewlineCount() {
    var count = 0;
    for (var runIndex = _runs.length - 1; runIndex >= 0; runIndex--) {
      final text = _runs[runIndex].text;
      for (var index = text.length - 1; index >= 0; index--) {
        if (text.codeUnitAt(index) != 0x0a) return count;
        count++;
      }
    }
    return count;
  }

  List<BulletinDescriptionRun> finish() {
    while (_runs.isNotEmpty) {
      final trimmed = _runs.last.text.replaceFirst(RegExp(r'\n+$'), '');
      if (trimmed.isEmpty) {
        _runs.removeLast();
      } else {
        _runs.last.text = trimmed;
        break;
      }
    }
    return List.unmodifiable(
      _runs
          .where((run) => run.text.isNotEmpty)
          .map(
            (run) => BulletinDescriptionRun(
              run.text,
              bold: run.bold,
              italic: run.italic,
              underline: run.underline,
            ),
          ),
    );
  }

  static String _decodeEntities(String text) =>
      text.replaceAllMapped(_entity, (match) {
        final token = match.group(1)!;
        if (!token.startsWith('#')) {
          return _namedEntities[token.toLowerCase()] ?? match.group(0)!;
        }
        final hexadecimal = token.length > 2 && token[1].toLowerCase() == 'x';
        final digits = token.substring(hexadecimal ? 2 : 1);
        final value = int.tryParse(digits, radix: hexadecimal ? 16 : 10);
        if (value == null || !_isSafeScalar(value)) return '\uFFFD';
        return String.fromCharCode(value);
      });

  static bool _isSafeScalar(int value) =>
      value == 0x09 ||
      value == 0x0a ||
      value == 0x0d ||
      (value >= 0x20 &&
          value <= 0x10ffff &&
          (value < 0xd800 || value > 0xdfff));
}

class _MutableRun {
  _MutableRun(this.text, this.bold, this.italic, this.underline);

  String text;
  final bool bold;
  final bool italic;
  final bool underline;
}

enum _InlineStyle { bold, italic, underline }

class _ListContext {
  _ListContext({required this.ordered});

  final bool ordered;
  int nextNumber = 1;
}
