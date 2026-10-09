import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/import/data/block_paginator.dart';
import 'package:abelnotes/features/import/data/frontmatter.dart';
import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/features/import/data/notion_importer.dart';
import 'package:abelnotes/features/import/data/obsidian_importer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:image/image.dart' as img;

Uint8List tinyPng() =>
    Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 4)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('frontmatter', () {
    test('tags list and string forms, hash stripped', () {
      expect(
          stripFrontmatter('---\ntags:\n  - uni\n  - "#lab"\n---\ncorpo')
              .tags,
          ['uni', 'lab']);
      expect(stripFrontmatter('---\ntags: a, b c\n---\nx').tags,
          ['a', 'b', 'c']);
      final r = stripFrontmatter('---\ntags: [x]\n---\ncorpo qui');
      expect(r.body, 'corpo qui');
    });

    test('no frontmatter or malformed yaml is harmless', () {
      expect(stripFrontmatter('# solo testo').body, '# solo testo');
      expect(stripFrontmatter('---\n: : :\n---\nok').body, 'ok');
    });
  });

  group('ObsidianImporter', () {
    late Directory vault;

    setUp(() async {
      vault = await Directory.systemTemp.createTemp('vault_test_');
      File('${vault.path}/.obsidian/app.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      File('${vault.path}/Nota.md').writeAsStringSync(
          '---\ntags: [scuola]\n---\n# Titolo\n\nvedi [[Altra|alias]] e ![[foto.png]]');
      File('${vault.path}/sub/Altra.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('contenuto');
      File('${vault.path}/allegati/foto.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(tinyPng());
    });

    tearDown(() => vault.delete(recursive: true));

    test('vault becomes draft: chapters, tags, wikilinks, embeds', () async {
      final draft = await ObsidianImporter().parse(vault.path);
      expect(draft.chapters, hasLength(2));
      expect(draft.chapters.map((c) => c.title),
          containsAll(['Nota', 'sub / Altra']));
      expect(draft.tags, ['scuola']);
      final nota =
          draft.chapters.firstWhere((c) => c.title == 'Nota').blocks;
      // Wikilink alias becomes a blue span, embed resolves by basename.
      final linkPara = nota.whereType<TextBlock>().firstWhere(
          (b) => b.plain.contains('alias'));
      expect(linkPara.spans.any((s) => s.text == 'alias' && s.color != null),
          isTrue);
      expect(nota.whereType<ImageBlock>(), hasLength(1));
      expect(draft.assets, hasLength(1));
    });

    test('hidden dirs skipped, empty vault throws', () async {
      final empty = await Directory.systemTemp.createTemp('vuoto_');
      addTearDown(() => empty.delete(recursive: true));
      expect(
          () => ObsidianImporter().parse(empty.path),
          throwsA(isA<ImportException>().having(
              (e) => e.code, 'code', ImportErrorCode.noMarkdownFiles)));
    });

    test('latin1 note is kept, binary note is reported, no abs paths',
        () async {
      File('${vault.path}/lat.md')
          .writeAsBytesSync([0x63, 0x61, 0x66, 0x66, 0xE8]); // "caffè"
      File('${vault.path}/bin.md')
          .writeAsBytesSync(List.generate(600, (i) => i % 7));
      final draft = await ObsidianImporter().parse(vault.path);
      final lat = draft.chapters.firstWhere((c) => c.title == 'lat');
      expect((lat.blocks.single as TextBlock).plain, 'caffè');
      expect(draft.chapters.any((c) => c.title == 'bin'), isFalse);
      expect(
          draft.issues.any((i) =>
              i.source == 'bin.md' && i.code == ImportIssueCode.fileUnreadable),
          isTrue);
      expect(draft.issues.every((i) => !i.source.startsWith('/')), isTrue);
    });

    test('dot-named notes kept, hidden folders skipped with a warning',
        () async {
      File('${vault.path}/..odd..md').writeAsStringSync('dots');
      File('${vault.path}/.secret/x.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('hidden');
      final draft = await ObsidianImporter().parse(vault.path);
      expect(draft.chapters.any((c) => c.title == '..odd.'), isTrue);
      expect(draft.chapters.any((c) => c.title.contains('x')), isFalse);
      final w = draft.issues
          .firstWhere((i) => i.code == ImportIssueCode.hiddenFoldersSkipped);
      expect(w.count, 1);
    });

    test('one warning per missing / remote image', () async {
      File('${vault.path}/img.md').writeAsStringSync(
          '![a](https://x.test/a.png)\n\n![[nope.png]]');
      final draft = await ObsidianImporter().parse(vault.path);
      final codes = draft.issues
          .where((i) => i.source == 'img.md')
          .map((i) => i.code)
          .toList();
      expect(codes, [
        ImportIssueCode.remoteImageSkipped,
        ImportIssueCode.imageNotFound,
      ]);
    });

    test('oversized note is skipped with a warning', () async {
      final big = File('${vault.path}/big.md')..createSync();
      big.writeAsBytesSync(List.filled(17 << 20, 0x61));
      final draft = await ObsidianImporter().parse(vault.path);
      expect(draft.chapters.any((c) => c.title == 'big'), isFalse);
      expect(
          draft.issues.any((i) =>
              i.source == 'big.md' && i.code == ImportIssueCode.fileTooLarge),
          isTrue);
    });
  });

  group('NotionImporter', () {
    Uint8List makeNotionZip() {
      const id = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
      final archive = Archive();
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add('Export/Pagina $id.md',
          utf8.encode('# Ciao\n\n![img](Pagina%20$id/img.png)\n\nvedi [Sub](Sub%20$id.md)'));
      add('Export/Pagina $id/img.png', tinyPng());
      add('Export/Sub $id.md', utf8.encode('sotto pagina'));
      add('Export/Db $id.csv', utf8.encode('nome,valore\r\na,"1,5"\r\n'));
      add('Export/Db ${id}_all.csv',
          utf8.encode('nome,valore\r\na,"1,5"\r\nb,2\r\n'));
      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    }

    test('detection, id stripping, links, csv preference', () async {
      final zip = makeNotionZip();
      expect(
          NotionImporter.looksLikeNotionExport(
              ZipDecoder().decodeBytes(zip)),
          isTrue);
      final draft =
          await NotionImporter().parse(zip, exportName: 'Export.zip');
      expect(draft.title, 'Export');
      expect(draft.chapters.map((c) => c.title),
          containsAll(['Export / Pagina', 'Export / Sub', 'Export / Db']));
      // Only the _all.csv variant becomes a chapter.
      expect(
          draft.chapters.where((c) => c.title.contains('Db')), hasLength(1));
      final db = draft.chapters.firstWhere((c) => c.title.contains('Db'));
      final table = db.blocks.single as TableBlock;
      expect(table.rows, hasLength(3)); // header + 2 rows (quoted comma ok)
      expect(table.rows[1], ['a', '1,5']);
      // Image resolved from URL-encoded path; internal link has no url suffix.
      final pagina =
          draft.chapters.firstWhere((c) => c.title == 'Export / Pagina');
      expect(pagina.blocks.whereType<ImageBlock>(), hasLength(1));
      final linkBlock = pagina.blocks
          .whereType<TextBlock>()
          .firstWhere((b) => b.plain.contains('Sub'));
      expect(linkBlock.plain, isNot(contains('.md')));
    });

    test('non-notion zip fails cleanly', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 4, utf8.encode('ciao')));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(
          () => NotionImporter().parse(zip, exportName: 'x.zip'),
          throwsA(isA<ImportException>().having(
              (e) => e.code, 'code', ImportErrorCode.noNotionContent)));
    });

    test('corrupt zip maps to zipUnreadable', () async {
      expect(
          () => NotionImporter()
              .parse(Uint8List.fromList([1, 2, 3, 4]), exportName: 'x.zip'),
          throwsA(isA<ImportException>().having(
              (e) => e.code, 'code', ImportErrorCode.zipUnreadable)));
    });

    test('zip bomb entry skipped, normal pages still import', () async {
      const id = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
      final archive = Archive();
      void add(String name, List<int> bytes) =>
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
      add('Ok $id.md', utf8.encode('fine'));
      add('Bomb $id.md', List.filled(70 << 20, 0x61));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final draft = await NotionImporter().parse(zip, exportName: 'x.zip');
      expect(draft.chapters.map((c) => c.title), ['Ok']);
      expect(
          draft.issues.any((i) => i.code == ImportIssueCode.zipEntryTooLarge),
          isTrue);
    });

    test('warnings carry readable decoded paths', () async {
      const id = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
      final archive = Archive();
      final md = utf8.encode('![x](Page%20$id/missing%20pic.png)');
      archive.addFile(ArchiveFile('Page $id.md', md.length, md));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final draft = await NotionImporter().parse(zip, exportName: 'x.zip');
      expect(draft.issues.single.arg, 'Page/missing pic.png');
    });
  });

  test('round-trip: obsidian draft → pages → PageData json → parse back',
      () async {
    final vault = await Directory.systemTemp.createTemp('vault_rt_');
    addTearDown(() => vault.delete(recursive: true));
    File('${vault.path}/N.md').writeAsStringSync(
        '# T\n\nparagrafo **ricco**\n\n- a\n- b\n\n```\ncode\n```');
    final draft = await ObsidianImporter().parse(vault.path);
    final pages = await BlockPaginator().paginate(draft.chapters.single.blocks);
    for (final page in pages) {
      final pd = PageData(
        pageId: 'p1',
        pageNumber: 1,
        width: BlockPaginator.pageW,
        height: BlockPaginator.pageH,
        layers: RenderingLayers(
          background: const BackgroundLayer(type: 'blank'),
          content: page.elements,
        ),
        assetReferences: page.assetRefs.toList(),
      );
      final decoded =
          PageData.fromJson(jsonDecode(jsonEncode(pd.toJson())));
      expect(decoded.layers.content.length, page.elements.length);
    }
  });
}
