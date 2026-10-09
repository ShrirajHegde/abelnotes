import 'package:abelnotes/features/import/data/import_limits.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/markdown_block_parser.dart';

/// Looks an embedded note up by its wikilink target.
typedef NoteLookup = ({String title, String body})? Function(String target);

/// Budget shared by every embed expansion of one top-level note, so a note
/// that embeds itself (or fans out) cannot grow without bound.
class EmbedBudget {
  int remainingChars = 1 << 21;
}

final _fence = RegExp(r'^[ \t]*(`{3,}|~{3,}).*$', multiLine: true);
final _inlineCode = RegExp(r'(`+)(?!`)[\s\S]*?(?<!`)\1(?!`)');
final _comment = RegExp(r'%%[\s\S]*?%%');
final _highlight = RegExp(r'==(?!\s)([^=\n]+?)(?<!\s)==');
final _callout = RegExp(r'^([ \t]*>[ \t]*)\[!([\w-]+)\][+-]?[ \t]*(.*)$',
    multiLine: true);
final _embed = RegExp(r'!\[\[([^\]\[]+?)\]\]');
final _wikilink = RegExp(r'\[\[([^\]\[]+?)\]\]');
final _footDef = RegExp(r'^\[\^([^\]\s]+)\]:[ \t]*', multiLine: true);
final _footRef = RegExp(r'\[\^([^\]\s]+)\]');
final _footInline = RegExp(r'\^\[([^\]\n]+)\]');
final _tag =
    RegExp(r'(?:^|(?<=\s))#([A-Za-z_][\w/-]*)', multiLine: true);

const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? '' : name.substring(i).toLowerCase();
}

/// Runs [transform] on the prose of [text], leaving fenced and inline code
/// untouched.
String _outsideCode(String text, String Function(String prose) transform) {
  final out = StringBuffer();
  var last = 0;
  final fences = _fence.allMatches(text).toList();
  var i = 0;
  while (i < fences.length) {
    final open = fences[i];
    final marker = open.group(1)!;
    int? closeEnd;
    var j = i + 1;
    for (; j < fences.length; j++) {
      final g = fences[j].group(1)!;
      if (g[0] == marker[0] && g.length >= marker.length) {
        closeEnd = fences[j].end;
        break;
      }
    }
    out.write(_proseWithInlineCode(text.substring(last, open.start), transform));
    final end = closeEnd ?? text.length;
    out.write(text.substring(open.start, end));
    last = end;
    i = closeEnd == null ? fences.length : j + 1;
  }
  out.write(_proseWithInlineCode(text.substring(last), transform));
  return out.toString();
}

String _proseWithInlineCode(
    String prose, String Function(String prose) transform) {
  final stash = <String>[];
  final masked = prose.replaceAllMapped(_inlineCode, (m) {
    stash.add(m.group(0)!);
    return '\u0001${stash.length - 1}\u0001';
  });
  return transform(masked).replaceAllMapped(RegExp('\u0001(\\d+)\u0001'),
      (m) => stash[int.parse(m.group(1)!)]);
}

/// Hashtags in the prose of [text] (not in code), without the `#`.
List<String> extractInlineTags(String text) {
  final tags = <String>{};
  _outsideCode(text, (prose) {
    for (final m in _tag.allMatches(prose)) {
      tags.add(m.group(1)!);
    }
    return prose;
  });
  return tags.toList();
}

/// Converts Obsidian-only syntax to what the Markdown parser understands.
/// Comments are dropped, callouts become quotes with a bold title, `==x==`
/// loses its markers, footnotes become `[n]` text, `![[Note]]` is inlined as
/// a quote (cycle/depth/size guarded) and `![[image]]` becomes an image.
String rewriteObsidianSyntax(
  String body, {
  required String source,
  required List<ImportIssue> issues,
  required NoteLookup lookupNote,
  required String selfKey,
  Set<String>? visiting,
  int depth = 0,
  EmbedBudget? budget,
}) {
  final chain = {...?visiting, selfKey};
  final bud = budget ?? EmbedBudget();
  return _outsideCode(body, (prose) {
    var t = prose.replaceAll(_comment, '');
    t = t.replaceAllMapped(_callout, (m) {
      final type = m.group(2)!;
      final title = m.group(3)!.trim();
      final shown = title.isNotEmpty
          ? title
          : '${type[0].toUpperCase()}${type.substring(1)}';
      final prefix = m.group(1)!;
      return '$prefix**$shown**\n${prefix.trimRight()}';
    });
    t = t.replaceAllMapped(_embed, (m) {
      final inner = m.group(1)!;
      final target = inner.split('|').first.split('#').first.split('^').first.trim();
      final ext = _ext(target);
      if (_imageExts.contains(ext)) {
        return '![](${Uri.encodeFull(target)})';
      }
      if (ext.isNotEmpty && ext != '.md') {
        issues.add(ImportIssue(
            source: source,
            code: ImportIssueCode.embedUnsupported,
            arg: target));
        return '[$target]';
      }
      final key = target.toLowerCase();
      if (depth >= ImportLimits.maxEmbedDepth ||
          chain.contains(key) ||
          bud.remainingChars <= 0) {
        issues.add(ImportIssue(
            source: source,
            code: ImportIssueCode.noteEmbedTooDeep,
            arg: target));
        return '[$target]';
      }
      final note = lookupNote(target);
      if (note == null) {
        issues.add(ImportIssue(
            source: source,
            code: ImportIssueCode.noteEmbedNotFound,
            arg: target));
        return '[$target]';
      }
      bud.remainingChars -= note.body.length;
      final inlined = rewriteObsidianSyntax(note.body,
          source: source,
          issues: issues,
          lookupNote: lookupNote,
          selfKey: key,
          visiting: chain,
          depth: depth + 1,
          budget: bud);
      final quoted = [
        '**${note.title}**',
        '',
        ...inlined.trim().split('\n'),
      ].map((l) => l.isEmpty ? '>' : '> $l').join('\n');
      return '\n\n$quoted\n\n';
    });
    t = t.replaceAllMapped(_wikilink, (m) {
      final parts = m.group(1)!.split('|');
      final target = parts.first.split('#').first.trim();
      final alias = (parts.length > 1 ? parts.last : parts.first).trim();
      return '[$alias]($kInternalLinkScheme${Uri.encodeFull(target)})';
    });
    t = t.replaceAllMapped(_highlight, (m) => m.group(1)!);
    t = t.replaceAllMapped(_footInline, (m) => ' (${m.group(1)})');
    t = t.replaceAllMapped(_footDef, (m) => '[${m.group(1)}] ');
    t = t.replaceAllMapped(_footRef, (m) => '[${m.group(1)}]');
    return t;
  });
}
