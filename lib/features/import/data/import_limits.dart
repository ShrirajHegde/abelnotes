import 'dart:convert';
import 'dart:typed_data';

/// Size guards shared by the foreign-format importers. Generous for real
/// notes, tight enough that a hostile or runaway input cannot exhaust memory.
class ImportLimits {
  static const int maxNoteBytes = 16 << 20;
  static const int maxImageBytes = 48 << 20;
  static const int maxZipEntryBytes = 64 << 20;
  static const int maxZipTotalBytes = 768 << 20;

  /// Entries that expand past this ratio are treated as zip bombs.
  static const int maxZipRatio = 200;
  static const int ratioCheckFloorBytes = 8 << 20;

  static const int maxPagesPerNote = 500;
  static const int maxEmbedDepth = 3;
  static const int maxChapterWarning = 200;
}

/// Decodes note text: strict UTF-8, then Latin-1 for legacy files. Returns
/// null for binary content (NUL bytes or mostly control characters).
({String text, bool fellBack})? decodeNoteText(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final body = start == 0 ? bytes : Uint8List.sublistView(bytes, start);
  final sample = body.length > 8192 ? body.sublist(0, 8192) : body;
  var control = 0;
  for (final b in sample) {
    if (b == 0) return null;
    if (b < 9 || (b > 13 && b < 32)) control++;
  }
  if (sample.isNotEmpty && control * 10 > sample.length) return null;
  try {
    return (text: utf8.decode(body), fellBack: false);
  } on FormatException {
    return (text: latin1.decode(body), fellBack: true);
  }
}
