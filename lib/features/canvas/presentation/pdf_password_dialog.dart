import 'package:flutter/material.dart';

import 'package:abelnotes/l10n/app_localizations.dart';

/// Asks for a PDF's password. Returns null when cancelled. [wrong] shows the
/// "try again" hint after a failed attempt.
Future<String?> showPdfPasswordDialog(BuildContext context,
    {required bool wrong}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PdfPasswordDialog(wrong: wrong),
  );
}

class _PdfPasswordDialog extends StatefulWidget {
  final bool wrong;
  const _PdfPasswordDialog({required this.wrong});

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.qiPdfPasswordTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.qiPdfPasswordBody),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.qiPdfPasswordHint,
              errorText: widget.wrong ? l10n.qiPdfPasswordWrong : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.csCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: Text(l10n.qiPdfPasswordOpen),
        ),
      ],
    );
  }
}
