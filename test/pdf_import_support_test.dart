import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/features/canvas/data/pdf_import_support.dart';

void main() {
  test('A4 and near-A4 pages keep the reference size', () {
    expect(pdfPageLogicalSize(595.28, 841.89), (w: 595.0, h: 842.0));
    expect(pdfPageLogicalSize(600, 845), (w: 595.0, h: 842.0));
  });

  test('other shapes keep their aspect at about A4 area', () {
    final land = pdfPageLogicalSize(842, 595);
    expect(land.w / land.h, closeTo(842 / 595, 0.01));
    final sq = pdfPageLogicalSize(300, 300);
    expect(sq.w, sq.h);
    expect(sq.w * sq.h, closeTo(595 * 842, 5000));
  });

  test('absurd sizes are bounded', () {
    final huge = pdfPageLogicalSize(14400, 14400);
    expect(huge.w, lessThan(1000));
    final tiny = pdfPageLogicalSize(20, 20);
    expect(tiny.w, greaterThan(500));
    final strip = pdfPageLogicalSize(14400, 20);
    expect(strip.w, lessThanOrEqualTo(4000));
    expect(strip.h, greaterThanOrEqualTo(40));
    expect(pdfPageLogicalSize(0, 10), (w: 595.0, h: 842.0));
  });
}
