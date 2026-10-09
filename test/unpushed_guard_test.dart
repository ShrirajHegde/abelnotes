import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/services/unpushed_guard.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

NotebookMetadata meta({String title = 'N', DateTime? at}) => NotebookMetadata(
    id: 'n', title: title, createdAt: DateTime(2026), modifiedAt: at ?? DateTime(2026));

DocumentStructure doc(List<String> files, {DateTime? stamp}) => DocumentStructure(
      notebookId: 'n',
      pages: [
        for (var i = 0; i < files.length; i++)
          PageEntry(
              pageId: 'p$i',
              pageNumber: i + 1,
              fileName: files[i],
              lastModified: stamp),
      ],
    );

bool check({
  Set<String> dirty = const {'page_001.json'},
  Map<String, String> known = const {'page_001.json': 'a', 'page_002.json': 'b'},
  Map<String, String> server = const {'page_001.json': 'a', 'page_002.json': 'b'},
  DocumentStructure? baseDoc,
  DocumentStructure? serverDoc,
  NotebookMetadata? baseMeta,
  NotebookMetadata? serverMeta,
}) =>
    serverMoveIsDisjoint(
      dirtyPageKeys: dirty,
      knownPageEtags: known,
      serverPageEtags: server,
      baseDocument: baseDoc ?? doc(['page_001.json', 'page_002.json']),
      serverDocument: serverDoc ?? doc(['page_001.json', 'page_002.json']),
      baseMetadata: baseMeta ?? meta(),
      serverMetadata: serverMeta ?? meta(),
    );

void main() {
  test('another page changed on the server: safe', () {
    expect(
        check(server: {'page_001.json': 'a', 'page_002.json': 'CHANGED'}),
        isTrue);
  });

  test('timestamps alone moving on the server are safe', () {
    expect(
        check(
            serverDoc: doc(['page_001.json', 'page_002.json'],
                stamp: DateTime(2027)),
            serverMeta: meta(at: DateTime(2027))),
        isTrue);
  });

  test('the page being pushed changed on the server: needs the editor', () {
    expect(
        check(server: {'page_001.json': 'CHANGED', 'page_002.json': 'b'}),
        isFalse);
  });

  test('a page unknown here that exists on the server is not ours to overwrite',
      () {
    expect(check(known: const {}, server: const {'page_001.json': 'x'}),
        isFalse);
  });

  test('a page deleted on the server: needs the editor', () {
    expect(check(server: const {'page_002.json': 'b'}), isFalse);
  });

  test('page list changed on the server: needs the editor', () {
    expect(
        check(
            serverDoc:
                doc(['page_001.json', 'page_002.json', 'page_003.json'])),
        isFalse);
    expect(
        check(serverDoc: doc(['page_002.json', 'page_001.json'])), isFalse);
  });

  test('renamed on the server: needs the editor', () {
    expect(check(serverMeta: meta(title: 'Other')), isFalse);
  });

  test('assets, meta and doc keys never block', () {
    expect(check(dirty: {'asset:x', 'meta', 'doc'}), isTrue);
  });
}
