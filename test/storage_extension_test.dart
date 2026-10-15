// Stored notebooks moved from .ncnote to .abelnote. Both spellings of one
// notebook must compare equal, or a rename half-done by another device would
// read as a deletion.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/config/app_config.dart';
import 'package:abelnotes/core/services/remote_store.dart';

import 'support/fake_remote_store.dart';

void main() {
  test('legacy names map to the new extension, others stay', () {
    expect(AppConfig.toStorageName('/AbelNotes/a_1.ncnote'),
        '/AbelNotes/a_1.abelnote');
    expect(AppConfig.toStorageName('/AbelNotes/a_1.abelnote'),
        '/AbelNotes/a_1.abelnote');
    expect(AppConfig.toStorageName('trash/x.meta.json'), 'trash/x.meta.json');
  });

  test('both spellings share a stem', () {
    expect(AppConfig.notebookStem('/AbelNotes/a_1.ncnote'), '/AbelNotes/a_1');
    expect(AppConfig.notebookStem('/AbelNotes/a_1.abelnote'), '/AbelNotes/a_1');
    expect(AppConfig.notebookStem('/AbelNotes/a_1.zip'), '/AbelNotes/a_1.zip');
  });

  test('the fake store renames and refuses to overwrite', () async {
    final s = FakeRemoteStore();
    s.files['/AbelNotes/a.ncnote'] = Uint8List.fromList([1]);
    s.files['/AbelNotes/b.ncnote'] = Uint8List.fromList([2]);
    s.files['/AbelNotes/b.abelnote'] = Uint8List.fromList([3]);

    await s.rename('/AbelNotes/a.ncnote', '/AbelNotes/a.abelnote');
    expect(s.files.keys, contains('/AbelNotes/a.abelnote'));
    expect(s.files.keys, isNot(contains('/AbelNotes/a.ncnote')));

    expect(() => s.rename('/AbelNotes/b.ncnote', '/AbelNotes/b.abelnote'),
        throwsA(isA<RemoteStoreException>()));
  });
}
