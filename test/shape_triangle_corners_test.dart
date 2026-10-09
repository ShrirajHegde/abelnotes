import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/render_engine.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

ShapeData _tri({double rotation = 0, List<double> vertices = const []}) =>
    ShapeData(
      shapeType: 'triangle',
      x1: 0,
      y1: 0,
      x2: 100,
      y2: 100,
      rotation: rotation,
      vertices: vertices,
    );

void main() {
  test('triangleCorners follows the apex direction the painter uses', () {
    expect(triangleCorners(_tri()).first, const Offset(50, 0));
    expect(triangleCorners(_tri(rotation: 3.141592653589793 / 2)).first,
        const Offset(100, 50));
    expect(triangleCorners(_tri(rotation: 3.141592653589793)).first,
        const Offset(50, 100));
  });

  test('explicit vertices win over bbox and rotation', () {
    final t = _tri(rotation: 0.3, vertices: [10, 10, 90, 20, 30, 80]);
    expect(triangleCorners(t),
        const [Offset(10, 10), Offset(90, 20), Offset(30, 80)]);
    expect(shapeBodyContains(t, const Offset(40, 40)), isTrue);
    expect(shapeBodyContains(t, const Offset(90, 90)), isFalse);
  });

  test('apex-right triangle body is on the right side of its bbox', () {
    final t = _tri(rotation: 3.141592653589793 / 2);
    expect(shapeBodyContains(t, const Offset(20, 50)), isTrue);
    expect(shapeBodyContains(t, const Offset(90, 5)), isFalse);
  });
}
