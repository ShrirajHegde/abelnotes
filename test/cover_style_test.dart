import 'package:abelnotes/shared/models/ncnote_format.dart';
import 'package:abelnotes/ui/primitives/sync_badge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every style round-trips through its stored key', () {
    for (final s in CoverStyle.values) {
      expect(CoverStyle.fromKey(s.key), s);
    }
  });

  test('old, missing and future keys fall back to the paper-type cover', () {
    expect(CoverStyle.fromKey('default'), CoverStyle.auto);
    expect(CoverStyle.fromKey(null), CoverStyle.auto);
    expect(CoverStyle.fromKey('marble_v9'), CoverStyle.auto);
  });

  test('coverStyle survives the metadata JSON round trip', () {
    final m = NotebookMetadata.fromJson(const {
      'id': 'x',
      'title': 't',
      'createdAt': '2026-01-01T00:00:00.000',
      'modifiedAt': '2026-01-01T00:00:00.000',
      'coverStyle': 'polka',
    });
    expect(NotebookMetadata.fromJson(m.toJson()).coverStyle, 'polka');
  });
}
