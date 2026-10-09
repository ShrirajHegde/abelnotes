import 'package:abelnotes/l10n/app_localizations.dart';

Set<String>? _defaults;

/// Shows the default first-chapter title in the UI language. New notebooks
/// store the English default; older ones stored the creation-time language.
String chapterDisplayTitle(AppLocalizations l10n, String title) {
  _defaults ??= {
    for (final l in AppLocalizations.supportedLocales)
      lookupAppLocalizations(l).nbDefaultChapterTitle,
  };
  return _defaults!.contains(title.trim()) ? l10n.nbDefaultChapterTitle : title;
}
