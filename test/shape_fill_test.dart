import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/shape_recognizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

List<StrokePoint> _trace(List<Offset> corners, {int perEdge = 20}) {
  final out = <StrokePoint>[];
  var t = 0;
  for (var i = 0; i < corners.length - 1; i++) {
    for (var k = 0; k < perEdge; k++) {
      final p = Offset.lerp(corners[i], corners[i + 1], k / perEdge)!;
      out.add(StrokePoint(x: p.dx, y: p.dy, timestamp: (t++) * 8));
    }
  }
  final last = corners.last;
  out.add(StrokePoint(x: last.dx, y: last.dy, timestamp: t * 8));
  return out;
}

void main() {
  const ink = 0xFF2A7A9E;
  final square = _trace(const [
    Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100), Offset(0, 0),
  ]);
  final triangle = _trace(const [
    Offset(0, 0), Offset(120, 30), Offset(30, 110), Offset(0, 0),
  ]);
  final line = _trace(const [Offset(0, 0), Offset(150, 40)]);

  test('closed shapes get a light tint of the ink when fill is on', () {
    for (final pts in [square, triangle]) {
      final s = recognizeShape(pts, color: ink, strokeWidth: 2, fill: true);
      expect(s, isNotNull);
      expect(s!.fillColor, 0x302A7A9E, reason: s.shapeType);
    }
  });

  test('no fill when off, and never on a line', () {
    for (final pts in [square, triangle]) {
      expect(recognizeShape(pts, color: ink, strokeWidth: 2)!.fillColor,
          isNull);
    }
    final l = recognizeShape(line, color: ink, strokeWidth: 2, fill: true);
    expect(l!.shapeType, 'line');
    expect(l.fillColor, isNull);
  });
}
