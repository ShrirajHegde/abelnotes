// A library refresh works from a snapshot of the rows; writing its card
// update back must not undo a sync status an upload settled meanwhile.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:abelnotes/core/services/file_service.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

void main() {
  late Directory tmp;
  late FileService fs;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('refresh_card_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    fs = FileService();
    await fs.init();
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('card refresh keeps sync status, etag and flags', () async {
    await fs.upsertNotebookMeta(
      id: 'n',
      title: 'Old',
      remotePath: '/AbelNotes/n.ncnote',
      etag: 'e1',
      localModifiedAt: DateTime(2026, 8, 26),
      syncStatus: 'synced',
      pageCount: 1,
    );
    await fs.setNotebookLocalOnly('n', true);
    await fs.markNotebookDirty('n');

    await fs.refreshNotebookCard(
      id: 'n',
      title: 'New',
      localModifiedAt: DateTime(2026, 9, 1),
      coverColor: 0xFF112233,
      paperType: 'grid',
      pageCount: 3,
    );

    final row = (await fs.getNotebookMeta('n'))!;
    expect(row['title'], 'New');
    expect(row['page_count'], 3);
    expect(row['paper_type'], 'grid');
    expect(row['sync_status'], 'modified');
    expect(row['etag'], 'e1');
    expect(row['local_only'], 1);
    expect(row['remote_path'], '/AbelNotes/n.ncnote');
  });
}
