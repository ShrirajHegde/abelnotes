import 'package:markdown/markdown.dart' as md;

import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Markdown → [ImportBlock] list. Pure Dart (no Flutter imports) so it can
/// run inside the parsing isolate and be unit-tested headless.
///
/// Image resolution is delegated to the adapter via [ImageBlockResolver]:
/// the adapter owns asset bytes, dimension probing and dedup, and returns a
/// ready [ImageBlock] or the reason it could not (the parser then reports
/// exactly one issue and keeps the alt text).
typedef ImageBlockResolver = ImageResolution Function(String src, String? alt);

class ImageResolution {
  final ImageBlock? block;
  final ImportIssueCode issue;

  /// Readable name for the issue; defaults to the raw `src`.
  final String? arg;

  const ImageResolution.ok(ImageBlock this.block)
      : issue = ImportIssueCode.imageNotFound,
        arg = null;
  const ImageResolution.fail(
      [this.issue = ImportIssueCode.imageNotFound, this.arg])
      : block = null;
}

/// Scheme used by adapters to mark internal links (Obsidian wikilinks,
/// Notion relative page links) that should render as a link-colored span
/// WITHOUT the ` (url)` suffix that external links get.
const String kInternalLinkScheme = 'internal-link://';

/// Link-blue used by the canvas for URL affordances (render_engine).
const int kLinkColor = 0xFF1565C0;

class MarkdownParser {
  final ImageBlockResolver? resolveImage;
  final void Function(ImportIssue issue)? onIssue;
  final String sourceName;

  MarkdownParser({this.resolveImage, this.onIssue, this.sourceName = ''});

  List<ImportBlock> parse(String source) {
    final out = <ImportBlock>[];
    // Pre-pass: extract display math ($$…$$) segments — the GFM parser has
    // no math support and would mangle LaTeX backslashes.
    for (final segment in _splitMathSegments(source)) {
      if (segment.isMath) {
        out.add(MathBlock(latex: segment.text.trim()));
        continue;
      }
      final doc = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
      );
      final nodes = doc.parse(segment.text);
      for (final node in nodes) {
        _walkBlock(node, 0, out);
      }
    }
    return out;
  }

  // ── math pre-pass ──

  List<({bool isMath, String text})> _splitMathSegments(String source) {
    final segments = <({bool isMath, String text})>[];
    final lines = source.split('\n');
    final buf = StringBuffer();
    final mathBuf = StringBuffer();
    var inMath = false;
    void flushText() {
      if (buf.isNotEmpty) {
        segments.add((isMath: false, text: buf.toString()));
        buf.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (!inMath) {
        // Single-line $$…$$ block.
        if (trimmed.length > 4 &&
            trimmed.startsWith(r'$$') &&
            trimmed.endsWith(r'$$')) {
          flushText();
          segments.add(
              (isMath: true, text: trimmed.substring(2, trimmed.length - 2)));
        } else if (trimmed == r'$$') {
          flushText();
          inMath = true;
        } else {
          buf.writeln(line);
        }
      } else {
        if (trimmed == r'$$') {
          segments.add((isMath: true, text: mathBuf.toString()));
          mathBuf.clear();
          inMath = false;
        } else {
          mathBuf.writeln(line);
        }
      }
    }
    // Unterminated math block: keep it as plain text so nothing is lost.
    if (inMath) buf.write(mathBuf);
    flushText();
    return segments;
  }

  // ── block walk ──

  void _walkBlock(md.Node node, int indent, List<ImportBlock> out) {
    if (node is md.Text) {
      _emitText(node.textContent, BlockKind.paragraph, indent, out);
      return;
    }
    if (node is! md.Element) return;
    switch (node.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.parse(node.tag.substring(1));
        _emitInline(node.children ?? const [],
            BlockKind.values[BlockKind.heading1.index + level - 1], indent, out);
      case 'p':
        _emitInline(node.children ?? const [], BlockKind.paragraph, indent, out);
      case 'ul':
        _walkList(node, indent, out, ordered: false);
      case 'ol':
        _walkList(node, indent, out,
            ordered: true, start: int.tryParse(node.attributes['start'] ?? '1') ?? 1);
      case 'blockquote':
        for (final child in node.children ?? const <md.Node>[]) {
          if (child is md.Element && child.tag == 'p') {
            _emitInline(child.children ?? const [], BlockKind.quote, indent, out);
          } else {
            _walkBlock(child, indent, out);
          }
        }
      case 'pre':
        // Fenced/indented code block: single monospace text block.
        final code = node.textContent;
        final text = code.endsWith('\n')
            ? code.substring(0, code.length - 1)
            : code;
        if (text.isNotEmpty) {
          out.add(TextBlock(
            spans: [TextSpanData(text: text, fontFamily: 'monospace')],
            plain: text,
            kind: BlockKind.code,
            indentLevel: indent,
          ));
        }
      case 'hr':
        out.add(const DividerBlock());
      case 'table':
        final rows = <List<String>>[];
        for (final section in node.children ?? const <md.Node>[]) {
          if (section is! md.Element) continue;
          for (final tr in section.children ?? const <md.Node>[]) {
            if (tr is! md.Element || tr.tag != 'tr') continue;
            rows.add([
              for (final cell in tr.children ?? const <md.Node>[])
                cell.textContent.trim()
            ]);
          }
        }
        if (rows.isNotEmpty) out.add(TableBlock(rows: rows));
      default:
        // Unknown container (html block, etc.): recurse or keep raw text.
        final children = node.children;
        if (children != null && children.isNotEmpty) {
          for (final child in children) {
            _walkBlock(child, indent, out);
          }
        } else if (node.textContent.trim().isNotEmpty) {
          _emitText(node.textContent, BlockKind.paragraph, indent, out);
        }
    }
  }

  void _walkList(md.Element list, int indent, List<ImportBlock> out,
      {required bool ordered, int start = 1}) {
    var n = start;
    for (final li in list.children ?? const <md.Node>[]) {
      if (li is! md.Element || li.tag != 'li') continue;
      final children = List<md.Node>.of(li.children ?? const []);

      // GFM task list: a leading <input type="checkbox"> child.
      String? taskPrefix;
      if (children.isNotEmpty &&
          children.first is md.Element &&
          (children.first as md.Element).tag == 'input') {
        final checked =
            (children.first as md.Element).attributes['checked'] == 'true';
        taskPrefix = checked ? '☑  ' : '☐  ';
        children.removeAt(0);
      }

      // Split the li into its own inline content and nested sub-lists.
      final inline = <md.Node>[];
      final nested = <md.Element>[];
      for (final child in children) {
        if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
          nested.add(child);
        } else if (child is md.Element && child.tag == 'p') {
          inline.addAll(child.children ?? const []);
        } else {
          inline.add(child);
        }
      }

      final prefix = taskPrefix ?? (ordered ? '$n.  ' : '•  ');
      final kind = taskPrefix != null
          ? BlockKind.task
          : (ordered ? BlockKind.ordered : BlockKind.bullet);
      _emitInline(inline, kind, indent, out, prefix: prefix);
      for (final sub in nested) {
        _walkList(sub, indent + 1, out,
            ordered: sub.tag == 'ol',
            start: int.tryParse(sub.attributes['start'] ?? '1') ?? 1);
      }
      n++;
    }
  }

  // ── inline spans ──

  /// Layout-only HTML tags that carry no content of their own.
  static final _htmlTag = RegExp(
      r'</?(?:div|span|aside|details|summary|p|b|i|u|em|strong|mark|sup|sub|kbd|center|font|section|article|figure|figcaption|br|hr)\b[^>]*>',
      caseSensitive: false);

  static String _stripHtml(String t) => t.replaceAllMapped(_htmlTag, (m) {
        final tag = m.group(0)!.toLowerCase();
        return tag.startsWith('<br') || tag.startsWith('<hr') ? '\n' : '';
      });

  /// `$x^2$` (Obsidian rules: no space inside the delimiters, no digit right
  /// after the closing one, so prices like "$5 and $10" stay text).
  static final _inlineMath =
      RegExp(r'(?<![\\$\d])\$(?!\s)([^$\n]*?[^\s$\\])\$(?!\d)');

  void _emitText(
      String text, BlockKind kind, int indent, List<ImportBlock> out) {
    final t = _stripHtml(text).trim();
    if (t.isEmpty) return;
    out.add(TextBlock(
      spans: [TextSpanData(text: t)],
      plain: t,
      kind: kind,
      indentLevel: indent,
    ));
  }

  void _emitInline(List<md.Node> nodes, BlockKind kind, int indent,
      List<ImportBlock> out,
      {String prefix = ''}) {
    if (prefix.isEmpty &&
        kind == BlockKind.paragraph &&
        nodes.length == 1 &&
        nodes.first is md.Text) {
      final m = _inlineMath.firstMatch(nodes.first.textContent.trim());
      if (m != null && m.group(0) == nodes.first.textContent.trim()) {
        out.add(MathBlock(latex: m.group(1)!));
        return;
      }
    }
    final spans = <TextSpanData>[];
    final images = <ImageBlock>[];
    if (prefix.isNotEmpty) spans.add(TextSpanData(text: prefix));
    _inlineSpans(nodes, const _InlineStyle(), spans, images);
    final merged = _mergeSpans(spans);
    final plain = merged.map((s) => s.text).join();
    if (plain.trim().isNotEmpty) {
      out.add(TextBlock(
        spans: merged,
        plain: plain,
        kind: kind,
        indentLevel: indent,
      ));
    }
    out.addAll(images);
  }

  void _inlineSpans(List<md.Node> nodes, _InlineStyle style,
      List<TextSpanData> spans, List<ImageBlock> images) {
    for (final node in nodes) {
      if (node is md.Text) {
        // Markdown soft line breaks arrive as '\n' inside the text.
        _textSpans(_stripHtml(node.textContent), style, spans);
      } else if (node is md.Element) {
        switch (node.tag) {
          case 'strong':
            _inlineSpans(node.children ?? const [], style.copyWith(bold: true),
                spans, images);
          case 'em':
            _inlineSpans(node.children ?? const [],
                style.copyWith(italic: true), spans, images);
          case 'del':
            _inlineSpans(node.children ?? const [],
                style.copyWith(strikethrough: true), spans, images);
          case 'code':
            spans.add(style
                .copyWith(monospace: true)
                .span(node.textContent));
          case 'a':
            final href = node.attributes['href'] ?? '';
            final label = node.textContent;
            if (href.startsWith(kInternalLinkScheme)) {
              // Internal link (wikilink / Notion page): blue span, inert v1.
              spans.add(style.copyWith(linkColor: true).span(label));
            } else {
              _inlineSpans(node.children ?? const [], style, spans, images);
              // The canvas auto-styles bare URLs and makes them
              // Ctrl+clickable — appending the target keeps it usable.
              if (href.isNotEmpty && href != label) {
                spans.add(style.span(' ($href)'));
              }
            }
          case 'img':
            final src = node.attributes['src'] ?? '';
            final alt = node.attributes['alt'];
            final res = resolveImage?.call(src, alt) ??
                const ImageResolution.fail();
            if (res.block != null) {
              images.add(res.block!);
            } else {
              if ((alt ?? '').isNotEmpty) spans.add(style.span('[$alt]'));
              onIssue?.call(ImportIssue(
                source: sourceName,
                code: res.issue,
                arg: res.arg ?? src,
              ));
            }
          case 'br':
            spans.add(style.span('\n'));
          default:
            _inlineSpans(node.children ?? const [], style, spans, images);
        }
      }
    }
  }

  /// Plain text with inline `$math$` shown as its italic LaTeX source.
  void _textSpans(String text, _InlineStyle style, List<TextSpanData> spans) {
    var last = 0;
    for (final m in _inlineMath.allMatches(text)) {
      if (m.start > last) spans.add(style.span(text.substring(last, m.start)));
      spans.add(style.copyWith(italic: true).span(m.group(1)!));
      last = m.end;
    }
    if (last < text.length) spans.add(style.span(text.substring(last)));
  }

  /// Merge adjacent spans with identical styling and drop empties, keeping
  /// the concat(spans)==plain invariant while minimising span count.
  List<TextSpanData> _mergeSpans(List<TextSpanData> spans) {
    final out = <TextSpanData>[];
    for (final s in spans) {
      if (s.text.isEmpty) continue;
      if (out.isNotEmpty) {
        final prev = out.last;
        if (prev.bold == s.bold &&
            prev.italic == s.italic &&
            prev.underline == s.underline &&
            prev.strikethrough == s.strikethrough &&
            prev.color == s.color &&
            prev.fontSize == s.fontSize &&
            prev.fontFamily == s.fontFamily) {
          out[out.length - 1] = prev.copyWith(text: prev.text + s.text);
          continue;
        }
      }
      out.add(s);
    }
    return out;
  }
}

class _InlineStyle {
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool monospace;
  final bool linkColor;

  const _InlineStyle({
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.monospace = false,
    this.linkColor = false,
  });

  _InlineStyle copyWith({
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? monospace,
    bool? linkColor,
  }) =>
      _InlineStyle(
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        strikethrough: strikethrough ?? this.strikethrough,
        monospace: monospace ?? this.monospace,
        linkColor: linkColor ?? this.linkColor,
      );

  TextSpanData span(String text) => TextSpanData(
        text: text,
        bold: bold,
        italic: italic,
        strikethrough: strikethrough,
        fontFamily: monospace ? 'monospace' : null,
        color: linkColor ? kLinkColor : null,
      );
}
