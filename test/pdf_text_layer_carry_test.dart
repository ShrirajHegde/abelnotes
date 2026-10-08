// A PDF page's text layer must survive edits that leave its source image
// alone, and go with that image when it is moved, cropped or deleted.

import 'package:flutter_test/flutter_test.dart';
import 'package:abelnotes/core/providers/canvas_provider.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

const _asset = 'abc_lecture.pdf_p1.png';

const _image = ContentElement.image(
  id: 'img',
  zIndex: 0,
  data: ImageData(x: 0, y: 0.181, width: 595, height: 841.637, assetPath: _asset, locked: true),
);

const _layer = PdfTextLayer(
  sourceAssetPath: _asset,
  runs: [PdfTextRun(text: 'Theorem', x: 40, y: 60, width: 50, height: 9)],
);

const _stroke = ContentElement.stroke(
  id: 's1',
  zIndex: 1,
  data: StrokeData(points: [StrokePoint(x: 100, y: 100), StrokePoint(x: 120, y: 110)]),
);

PageData _page(List<ContentElement> content, {PdfTextLayer? layer}) => PageData(
      pageId: 'p',
      pageNumber: 1,
      width: 595,
      height: 842,
      layers: RenderingLayers(content: content),
      pdfTextLayer: layer,
    );

void main() {
  final before = _page([_image], layer: _layer);

  test('writing on the page keeps the text layer', () {
    final after = carryPdfTextLayer(before, _page([_image, _stroke]));
    expect(after.pdfTextLayer, _layer);
  });

  test('erasing everything but the PDF keeps it', () {
    final withInk = _page([_image, _stroke], layer: _layer);
    expect(carryPdfTextLayer(withInk, _page([_image])).pdfTextLayer, _layer);
  });

  test('a copy of the page with new element ids keeps it', () {
    final copy = _page([const ContentElement.image(id: 'img2', zIndex: 0, data: ImageData(
        x: 0, y: 0.181, width: 595, height: 841.637, assetPath: _asset, locked: true))]);
    expect(carryPdfTextLayer(before, copy).pdfTextLayer, _layer);
  });

  test('moving the PDF image drops it', () {
    final moved = _page([const ContentElement.image(id: 'img', zIndex: 0, data: ImageData(
        x: 30, y: 0.181, width: 595, height: 841.637, assetPath: _asset, locked: true))]);
    expect(carryPdfTextLayer(before, moved).pdfTextLayer, isNull);
  });

  test('cropping (new asset) or deleting the PDF image drops it', () {
    final cropped = _page([const ContentElement.image(id: 'img', zIndex: 0, data: ImageData(
        x: 0, y: 0.181, width: 595, height: 400, assetPath: 'abc_cropped.png', locked: true))]);
    expect(carryPdfTextLayer(before, cropped).pdfTextLayer, isNull);
    expect(carryPdfTextLayer(before, _page([_stroke])).pdfTextLayer, isNull);
  });

  test('pages without a text layer are left as they are', () {
    final plain = _page([_stroke]);
    expect(carryPdfTextLayer(_page([]), plain), same(plain));
  });
}
