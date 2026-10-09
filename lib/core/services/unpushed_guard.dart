import 'package:abelnotes/shared/models/ncnote_format.dart';

/// Whether a closed notebook's pending pages can go up although the server
/// moved since this device last synced it.
///
/// Safe only when the server's moves are elsewhere: none of the pages being
/// pushed changed there, and the page list and metadata match the baseline
/// (timestamps aside). Anything else needs the editor's merge.
bool serverMoveIsDisjoint({
  required Set<String> dirtyPageKeys,
  required Map<String, String> knownPageEtags,
  required Map<String, String> serverPageEtags,
  required DocumentStructure baseDocument,
  required DocumentStructure serverDocument,
  required NotebookMetadata baseMetadata,
  required NotebookMetadata serverMetadata,
}) {
  for (final k in dirtyPageKeys) {
    if (k == 'meta' || k == 'doc' || k.startsWith('asset:')) continue;
    if (serverPageEtags[k] != knownPageEtags[k]) return false;
  }
  List<PageEntry> norm(DocumentStructure d) =>
      [for (final e in d.pages) e.copyWith(lastModified: null)];
  final a = norm(baseDocument);
  final b = norm(serverDocument);
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return baseMetadata.copyWith(modifiedAt: serverMetadata.modifiedAt) ==
      serverMetadata;
}
