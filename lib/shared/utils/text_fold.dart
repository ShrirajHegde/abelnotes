const _groups = {
  'a': 'àáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ďđ',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥħ',
  'i': 'ìíîïĩīĭįı',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľŀł',
  'n': 'ñńņň',
  'o': 'òóôõöøōŏő',
  'r': 'ŕŗř',
  's': 'śŝşš',
  't': 'ţťŧ',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
};

final _foldMap = {
  for (final e in _groups.entries)
    for (final r in e.value.runes) r: e.key,
};

/// Lower-cases and strips Latin diacritics, one output code unit per input
/// code unit so match offsets stay valid on the original string.
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    b.write(_foldMap[r] ?? String.fromCharCode(r));
  }
  return b.toString();
}
