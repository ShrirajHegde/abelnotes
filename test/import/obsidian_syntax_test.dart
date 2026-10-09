import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/markdown_block_parser.dart';
import 'package:abelnotes/features/import/data/obsidian_syntax.dart';

void main() {
  final notes = <String, String>{
    'other': 'other body',
    'a': 'A says ![[b]]',
    'b': 'B says ![[a]]',
  };
  NoteLookup lookup(List<String> seen) => (t) {
        seen.add(t);
        final b = notes[t.toLowerCase()];
        return b == null ? null : (title: t, body: b);
      };

  String rw(String s, {List<ImportIssue>? issues}) => rewriteObsidianSyntax(
        s,
        source: 'n.md',
        issues: issues ?? [],
        lookupNote: lookup([]),
        selfKey: 'n',
      );

  test('comments are stripped, also across lines', () {
    expect(rw('a %%hidden%% b\n%%\nmulti\nline\n%% c'), 'a  b\n c');
  });

  test('callout becomes a quote with a bold title', () {
    expect(rw('> [!note] My title\n> body'), '> **My title**\n>\n> body');
    expect(rw('> [!warning]-\n> body'), '> **Warning**\n>\n> body');
  });

  test('highlight and footnote markers', () {
    expect(rw('==key== idea'), 'key idea');
    expect(rw('x^[inline] y[^1]\n\n[^1]: the note'),
        'x (inline) y[1]\n\n[1] the note');
  });

  test('code is left alone', () {
    const src = '```\n%%keep%% ==x==\n```\n`==y== %%z%%`';
    expect(rw(src), src);
  });

  test('note embed is inlined as a quote; cycles stop', () {
    final issues = <ImportIssue>[];
    final out = rw('![[other]]', issues: issues);
    expect(out, contains('> **other**'));
    expect(out, contains('> other body'));
    final cyc = rewriteObsidianSyntax('![[a]]',
        source: 'n.md',
        issues: issues,
        lookupNote: lookup([]),
        selfKey: 'n');
    expect(cyc, contains('A says'));
    expect(cyc, contains('B says'));
    expect(issues.any((i) => i.code == ImportIssueCode.noteEmbedTooDeep),
        isTrue);
  });

  test('missing note and non-image files are reported, not dropped', () {
    final issues = <ImportIssue>[];
    final out = rw('![[ghost]] ![[doc.pdf]]', issues: issues);
    expect(out, '[ghost] [doc.pdf]');
    expect(issues.map((i) => i.code), [
      ImportIssueCode.noteEmbedNotFound,
      ImportIssueCode.embedUnsupported,
    ]);
  });

  test('inline tags outside code', () {
    expect(extractInlineTags('# Title\n\nsome #idea and #a/b, `#no`\n\n```\n#x\n```'),
        ['idea', 'a/b']);
  });

  group('math and html in the parser', () {
    test('sole inline math paragraph becomes a MathBlock', () {
      final blocks = MarkdownParser().parse(r'$E=mc^2$');
      expect((blocks.single as MathBlock).latex, 'E=mc^2');
    });

    test('inline math inside text keeps its source, prices stay text', () {
      final b = MarkdownParser()
          .parse(r'see $x^2$ and costs $5 or $10')
          .single as TextBlock;
      expect(b.plain, r'see x^2 and costs $5 or $10');
    });

    test('layout html tags are stripped', () {
      final blocks = MarkdownParser().parse('<div>raw html</div>');
      expect((blocks.single as TextBlock).plain, 'raw html');
    });
  });
}
