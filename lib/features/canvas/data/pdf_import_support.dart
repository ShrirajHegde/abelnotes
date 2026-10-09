import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

/// Why a PDF could not be opened for import. The UI maps each case to a
/// localized message; [PdfOpenException.toString] stays plain English.
enum PdfOpenFailure { notPdf, corrupt, empty, unsupported, passwordCancelled }

class PdfOpenException implements Exception {
  final PdfOpenFailure failure;
  final Object? cause;

  const PdfOpenException(this.failure, [this.cause]);

  @override
  String toString() => 'PdfOpenException: ${failure.name}';
}

/// FPDF_ERR_SECURITY, as reported through [PdfException.errorCode].
const int _errSecurity = 5;

bool _hasPdfHeader(Uint8List bytes) {
  final n = math.min(bytes.length, 1024);
  for (var i = 0; i + 4 < n; i++) {
    if (bytes[i] == 0x25 &&
        bytes[i + 1] == 0x50 &&
        bytes[i + 2] == 0x44 &&
        bytes[i + 3] == 0x46 &&
        bytes[i + 4] == 0x2D) {
      return true;
    }
  }
  return false;
}

/// Opens [bytes] with pdfrx before any import UI is shown. [askPassword]
/// receives `wrong: true` on every retry and returns null to cancel.
Future<PdfDocument> openPdfForImport(
  Uint8List bytes, {
  required Future<String?> Function(bool wrong) askPassword,
}) async {
  if (!_hasPdfHeader(bytes)) {
    throw const PdfOpenException(PdfOpenFailure.notPdf);
  }
  await pdfrxFlutterInitialize();
  var attempts = 0;
  try {
    final doc = await PdfDocument.openData(
      bytes,
      passwordProvider: () => askPassword(attempts++ > 0),
    );
    if (doc.pages.isEmpty) {
      await doc.dispose();
      throw const PdfOpenException(PdfOpenFailure.empty);
    }
    return doc;
  } on PdfPasswordException catch (e) {
    throw PdfOpenException(PdfOpenFailure.passwordCancelled, e);
  } on PdfOpenException {
    rethrow;
  } on PdfException catch (e) {
    throw PdfOpenException(
      e.errorCode == _errSecurity
          ? PdfOpenFailure.unsupported
          : PdfOpenFailure.corrupt,
      e,
    );
  }
}

/// Logical (notebook-point) size for a PDF page shown full-bleed: the page
/// keeps the source aspect ratio at roughly A4 area, or reuses
/// [refW]x[refH] when the aspect already matches within 1%.
({double w, double h}) pdfPageLogicalSize(
  double srcW,
  double srcH, {
  double refW = 595.0,
  double refH = 842.0,
}) {
  if (srcW <= 0 || srcH <= 0 || !srcW.isFinite || !srcH.isFinite) {
    return (w: refW, h: refH);
  }
  final aspect = srcW / srcH;
  if ((aspect / (refW / refH) - 1).abs() < 0.01) return (w: refW, h: refH);
  final area = refW * refH;
  var h = math.sqrt(area / aspect);
  var w = h * aspect;
  const maxSide = 4000.0;
  const minSide = 40.0;
  final longest = math.max(w, h);
  if (longest > maxSide) {
    final k = maxSide / longest;
    w *= k;
    h *= k;
  }
  w = math.max(w, minSide);
  h = math.max(h, minSide);
  return (w: w.roundToDouble(), h: h.roundToDouble());
}
