import 'package:abelnotes/features/import/data/import_models.dart';
import 'package:abelnotes/l10n/app_localizations.dart';

/// Localized sentence for one report line. Importers only emit codes.
String importIssueText(AppLocalizations l10n, ImportIssue i) {
  final arg = i.arg ?? '';
  final count = i.count ?? 0;
  return switch (i.code) {
    ImportIssueCode.remoteImageSkipped => l10n.qiIssueRemoteImage(arg),
    ImportIssueCode.imageNotFound => l10n.qiIssueImageNotFound(arg),
    ImportIssueCode.imageUnreadable => l10n.qiIssueImageUnreadable(arg),
    ImportIssueCode.attachmentUnsupported =>
      l10n.qiIssueAttachmentUnsupported(arg),
    ImportIssueCode.attachmentTooLarge => l10n.qiIssueAttachmentTooLarge(arg),
    ImportIssueCode.embedUnsupported => l10n.qiIssueEmbedUnsupported(arg),
    ImportIssueCode.noteEmbedNotFound => l10n.qiIssueNoteEmbedNotFound(arg),
    ImportIssueCode.noteEmbedTooDeep => l10n.qiIssueNoteEmbedSkipped(arg),
    ImportIssueCode.fileUnreadable => l10n.qiIssueFileUnreadable,
    ImportIssueCode.fileTooLarge => l10n.qiIssueFileTooLarge(count),
    ImportIssueCode.encodingFallback => l10n.qiIssueEncodingFallback,
    ImportIssueCode.csvUnreadable => l10n.qiIssueCsvUnreadable,
    ImportIssueCode.zipEntryTooLarge => l10n.qiIssueZipEntryTooLarge(count),
    ImportIssueCode.zipTotalTooLarge => l10n.qiIssueZipTotalTooLarge(count),
    ImportIssueCode.hiddenFoldersSkipped => l10n.qiIssueHiddenFolders(count),
    ImportIssueCode.tooManyChapters => l10n.qiIssueTooManyChapters(count),
    ImportIssueCode.pagesTruncated => l10n.qiIssuePagesTruncated(count),
    ImportIssueCode.oneNoteElementsSkipped => l10n.qiIssueOneNoteSkipped(count),
  };
}

/// Localized text for an error that aborted a foreign-format import.
String importErrorText(AppLocalizations l10n, Object error) {
  if (error is ImportException) {
    final msg = switch (error.code) {
      ImportErrorCode.noMarkdownFiles => l10n.qiErrNoMarkdown,
      ImportErrorCode.noNotionContent => l10n.qiErrNoNotionContent,
      ImportErrorCode.nothingImportable => l10n.qiErrNothingImportable,
      ImportErrorCode.zipUnreadable => l10n.qiErrZipUnreadable,
      ImportErrorCode.noOneNotePages => l10n.qiErrNoOneNotePages,
    };
    return l10n.libErrorImport(msg);
  }
  return l10n.libErrorImport(l10n.qiErrUnexpected);
}
