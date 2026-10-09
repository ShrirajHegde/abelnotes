// The sync engine must tell "the server says it is gone" from "I could not
// ask": only the first may turn a notebook into a kept-here copy.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/core/services/remote_store.dart';
import 'package:abelnotes/core/services/sync_service.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

import 'support/fake_remote_store.dart';

class _WebDavLikeStore extends FakeRemoteStore {
  bool failing = false;

  @override
  bool get nullVersionMeansAbsent => false;

  @override
  Future<String?> getVersion(String remotePath) async {
    if (failing) throw RemoteStoreException('PROPFIND status 500', 500);
    if (!files.containsKey(remotePath)) {
      throw RemoteStoreException('PROPFIND 404', 404);
    }
    return super.getVersion(remotePath);
  }

  @override
  Future<String?> getVersionFast(String remotePath) async => null;
}

void main() {
  final metadata = NotebookMetadata(
    id: 'nb',
    title: 'T',
    createdAt: DateTime.utc(2020),
    modifiedAt: DateTime.utc(2020),
  );
  const document = DocumentStructure(notebookId: 'nb', pages: []);

  test('remoteFileAbsent: 404 is absence, any other failure is not', () async {
    final store = _WebDavLikeStore();
    final sync = SyncService(store);
    await store.uploadFile('/AbelNotes/nb.ncnote', Uint8List(4));

    expect(await sync.remoteFileAbsent('/AbelNotes/nb.ncnote'), isFalse);
    expect(await sync.remoteFileAbsent('/AbelNotes/other.ncnote'), isTrue);

    store.failing = true;
    await expectLater(sync.remoteFileAbsent('/AbelNotes/other.ncnote'),
        throwsA(isA<RemoteStoreException>()));
  });

  test('deltaFolderExists(fresh) sees a folder deleted by another device',
      () async {
    final store = _WebDavLikeStore();
    final sync = SyncService(store);
    await sync.syncDelta(
      notebookId: 'nb',
      metadata: metadata,
      document: document,
      dirtyPages: const {},
    );
    expect(await sync.deltaFolderExists('nb'), isTrue);

    store.files.removeWhere((k, _) => k.startsWith('/AbelNotes/_delta/nb/'));
    // The session cache still says alive; a fresh check must ask the server.
    expect(await sync.deltaFolderExists('nb'), isTrue);
    expect(await sync.deltaFolderExists('nb', fresh: true), isFalse);
  });

  test('getPageVersions reports missing pages as null', () async {
    final store = _WebDavLikeStore();
    final sync = SyncService(store);
    await store.uploadFile('/AbelNotes/_delta/nb/pages/page_001.json', Uint8List(2));

    final v = await sync.getPageVersions('nb', ['page_001.json', 'page_002.json']);
    expect(v['page_001.json'], isNotNull);
    expect(v['page_002.json'], isNull);
  });

  test('without a server a network call raises NoRemoteException', () async {
    final sync = SyncService(null);
    expect(sync.isOffline, isTrue);
    await expectLater(sync.listRemoteNotebooks(), throwsA(isA<NoRemoteException>()));
    expect(NoRemoteException().toString(), isNot(contains('solo-locale')));
  });
}
