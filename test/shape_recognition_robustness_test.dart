// Robustness harness for freehand shape recognition: synthesises many hand-
// drawn-looking stroke variants per figure, feeds them to recognizeShape()
// and prints a confusion matrix (expected figure x recognised shape).
//
// Decisions pinned here (see shape_recognizer.dart for the thresholds):
//  - a square, at ANY rotation, snaps to a clean square: `rectangle` (rotated
//    to the drawn angle) or, when drawn as a diamond (~45 deg), `rhombus`;
//  - a non-square rhombus snaps to `rhombus` (never rectangle);
//  - an ellipse snaps to an oval `circle` shape (non-square bbox);
//  - open strokes and wobbly curves stay freehand (`none`).

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:abelnotes/features/canvas/data/shape_recognizer.dart';
import 'package:abelnotes/shared/models/ncnote_format.dart';

// ── geometry helpers ─────────────────────────────────────────────

Offset _rot(Offset p, double a, [Offset c = Offset.zero]) {
  final ca = cos(a), sa = sin(a);
  final d = p - c;
  return c + Offset(d.dx * ca - d.dy * sa, d.dx * sa + d.dy * ca);
}

double _distToSeg(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (l2 == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

double _distToPoly(Offset p, List<Offset> poly) {
  var best = double.infinity;
  for (var i = 0; i + 1 < poly.length; i++) {
    best = min(best, _distToSeg(p, poly[i], poly[i + 1]));
  }
  return best;
}

List<Offset> _densify(List<Offset> poly, {int per = 40}) {
  final out = <Offset>[];
  for (var i = 0; i + 1 < poly.length; i++) {
    for (var k = 0; k < per; k++) {
      out.add(Offset.lerp(poly[i], poly[i + 1], k / per)!);
    }
  }
  out.add(poly.last);
  return out;
}

/// Mean symmetric distance between two outlines, relative to [scale].
double _outlineError(List<Offset> a, List<Offset> b, double scale) {
  final da = _densify(a), db = _densify(b);
  double s1 = 0, s2 = 0;
  for (final p in da) {
    s1 += _distToPoly(p, b);
  }
  for (final p in db) {
    s2 += _distToPoly(p, a);
  }
  return (s1 / da.length + s2 / db.length) / 2 / scale;
}

/// Closed outline of a recognised shape exactly as the renderer draws it.
List<Offset> outlineOf(ShapeData s) {
  final l = min(s.x1, s.x2), r = max(s.x1, s.x2);
  final t = min(s.y1, s.y2), b = max(s.y1, s.y2);
  final c = Offset((l + r) / 2, (t + b) / 2);
  List<Offset> rotated(List<Offset> pts) =>
      [for (final p in pts) _rot(p, s.rotation, c)];
  switch (s.shapeType) {
    case 'line':
      return [Offset(s.x1, s.y1), Offset(s.x2, s.y2)];
    case 'rectangle':
      return rotated([
        Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b), Offset(l, t)
      ]);
    case 'rhombus':
      return rotated([
        Offset(c.dx, t), Offset(r, c.dy), Offset(c.dx, b), Offset(l, c.dy),
        Offset(c.dx, t)
      ]);
    case 'circle':
      return rotated([
        for (var i = 0; i <= 120; i++)
          Offset(c.dx + (r - l) / 2 * cos(2 * pi * i / 120),
              c.dy + (b - t) / 2 * sin(2 * pi * i / 120))
      ]);
    case 'triangle':
      if (s.vertices.length == 6) {
        final v = s.vertices;
        return [
          Offset(v[0], v[1]), Offset(v[2], v[3]), Offset(v[4], v[5]),
          Offset(v[0], v[1])
        ];
      }
      final q = ((s.rotation / (pi / 2)).round()) % 4;
      final isCard = (s.rotation - (s.rotation / (pi / 2)).round() * (pi / 2))
              .abs() <
          1e-3;
      if (isCard) {
        final qq = q < 0 ? q + 4 : q;
        switch (qq) {
          case 0:
            return [Offset(c.dx, t), Offset(l, b), Offset(r, b), Offset(c.dx, t)];
          case 1:
            return [Offset(r, c.dy), Offset(l, t), Offset(l, b), Offset(r, c.dy)];
          case 2:
            return [Offset(c.dx, b), Offset(r, t), Offset(l, t), Offset(c.dx, b)];
          default:
            return [Offset(l, c.dy), Offset(r, b), Offset(r, t), Offset(l, c.dy)];
        }
      }
      return rotated(
          [Offset(c.dx, t), Offset(l, b), Offset(r, b), Offset(c.dx, t)]);
  }
  return [];
}

bool _finite(ShapeData s) =>
    [s.x1, s.y1, s.x2, s.y2, s.rotation, ...s.vertices].every((v) => v.isFinite);

// ── stroke synthesis ─────────────────────────────────────────────

class Variant {
  Variant(this.cls, this.points, this.ideal, this.scale, this.tag);
  final String cls;
  final List<StrokePoint> points;
  final List<Offset> ideal; // closed/open ideal outline in page coords ([] = none)
  final double scale; // max bbox dimension of the ideal outline
  final String tag;
}

/// Sharp polygon outline (closed, first==last) -> rounded outline.
List<Offset> _roundCorners(List<Offset> poly, double frac) {
  if (frac <= 0) return poly;
  final n = poly.length - 1;
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final prev = poly[(i + n - 1) % n], cur = poly[i], next = poly[(i + 1) % n];
    final d1 = (prev - cur), d2 = (next - cur);
    final a = cur + d1 / d1.distance * min(d1.distance * frac, d1.distance / 2);
    final b = cur + d2 / d2.distance * min(d2.distance * frac, d2.distance / 2);
    for (var k = 0; k <= 8; k++) {
      final t = k / 8;
      out.add(Offset(
        (1 - t) * (1 - t) * a.dx + 2 * (1 - t) * t * cur.dx + t * t * b.dx,
        (1 - t) * (1 - t) * a.dy + 2 * (1 - t) * t * cur.dy + t * t * b.dy,
      ));
    }
  }
  out.add(out.first);
  return out;
}

class _Path {
  _Path(this.pts) {
    cum = [0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
    }
    total = cum.last;
  }
  final List<Offset> pts;
  late final List<double> cum;
  late final double total;

  Offset at(double s, {bool closed = true}) {
    if (closed) {
      s = s % total;
      if (s < 0) s += total;
    } else {
      s = s.clamp(0.0, total);
    }
    var lo = 0, hi = cum.length - 1;
    while (hi - lo > 1) {
      final m = (lo + hi) ~/ 2;
      if (cum[m] <= s) {
        lo = m;
      } else {
        hi = m;
      }
    }
    final seg = cum[hi] - cum[lo];
    return seg == 0 ? pts[lo] : Offset.lerp(pts[lo], pts[hi], (s - cum[lo]) / seg)!;
  }

  double closestS(Offset p) {
    var best = double.infinity, bs = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final d = (pts[i] - p).distance;
      if (d < best) {
        best = d;
        bs = cum[i];
      }
    }
    return bs;
  }
}

class _Sampler {
  _Sampler(this.r);
  final Random r;
  double u(double a, double b) => a + r.nextDouble() * (b - a);
  double logU(double a, double b) => exp(u(log(a), log(b)));
  double gauss() {
    final a = max(r.nextDouble(), 1e-9), b = r.nextDouble();
    return sqrt(-2 * log(a)) * cos(2 * pi * b);
  }

  /// Turns a path into a noisy, unevenly sampled stroke.
  List<StrokePoint> stroke(
    _Path path,
    double startS,
    double travel, {
    required double scale,
    bool closed = true,
    bool reverse = false,
  }) {
    // pen samples every ~1.5-9 px of page space (slow..fast), at least 14
    final n = (travel / u(1.5, 9)).clamp(14, 400).round();
    final base = travel / n;
    final wob = u(0.002, 0.025) * scale;
    final jit = u(0.1, 0.6); // digitiser noise, px, independent of size
    final waves = List.generate(
        3, (_) => [u(0.1, 0.6) * travel, u(0, 2 * pi), u(0, 2 * pi), u(0.4, 1)]);
    final spd = [u(0, 2 * pi), u(0.2, 0.6)];
    final out = <StrokePoint>[];
    var s = 0.0, k = 0;
    while (s <= travel) {
      final dir = reverse ? -1.0 : 1.0;
      final p = path.at(startS + dir * s, closed: closed);
      var dx = 0.0, dy = 0.0;
      for (final w in waves) {
        dx += sin(2 * pi * s / w[0] + w[1]) * w[3] * wob / 1.7;
        dy += sin(2 * pi * s / w[0] + w[2]) * w[3] * wob / 1.7;
      }
      dx += gauss() * jit;
      dy += gauss() * jit;
      final x = p.dx + dx, y = p.dy + dy;
      out.add(StrokePoint(x: x, y: y, timestamp: k * 8));
      if (r.nextDouble() < 0.05) {
        out.add(StrokePoint(x: x, y: y, timestamp: k * 8)); // duplicate sample
      }
      final edgeSlow = (s < 0.06 * travel || s > 0.94 * travel) ? 0.35 : 1.0;
      final speed = (1 + spd[1] * sin(spd[0] + 6 * s / travel)) * edgeSlow;
      s += base * speed * (r.nextDouble() < 0.1 ? u(0.2, 2.5) : 1);
      k++;
    }
    // jitter the last sample (pen lift flick)
    if (out.length > 3 && r.nextDouble() < 0.5) {
      final l = out.last;
      out[out.length - 1] =
          StrokePoint(x: l.x + gauss() * 0.01 * scale, y: l.y + gauss() * 0.01 * scale);
    }
    return out;
  }
}

typedef _Gen = Variant Function(int seed);

Offset _centre(_Sampler g) => Offset(g.u(600, 1200), g.u(600, 1200));

List<Offset> _xf(List<Offset> poly, double sx, double sy, double rot, double size,
        Offset c) =>
    [for (final p in poly) _rot(Offset(p.dx * sx, p.dy * sy) * size, rot) + c];

/// Closed-figure variant: [unit] is the sharp outline (closed, first==last).
Variant _closed(
  String cls,
  int seed,
  List<Offset> unit, {
  double sx = 1,
  double sy = 1,
  double? rot,
  double round = 0,
  bool smooth = false, // circle/ellipse: no corners to start from
  double? size,
  String tag = '',
}) {
  final g = _Sampler(Random(seed));
  final sz = size ?? g.logU(20, 900);
  final c = _centre(g);
  final th = rot ?? g.u(0, 2 * pi);
  // 25 % of the variants are tiny (20..60), 25 % huge (350..900).
  final ideal = _xf(unit, sx, sy, th, sz, c);
  final drawn = _roundCorners(_xf(unit, sx, sy, th, sz, c), round);
  final path = _Path(drawn);
  final reverse = g.r.nextBool();
  // start: at a sharp corner, mid-edge or random
  final nCorn = unit.length - 1;
  final mode = g.r.nextInt(3);
  double startS;
  if (smooth || mode == 2) {
    startS = g.u(0, path.total);
  } else if (mode == 0) {
    startS = path.closestS(ideal[g.r.nextInt(nCorn)]);
  } else {
    final i = g.r.nextInt(nCorn);
    startS = path.closestS(Offset.lerp(ideal[i], ideal[i + 1], g.u(0.35, 0.65))!);
  }
  // closing: exact / overshoot up to 8 % / gap up to 6 %
  final close = g.r.nextInt(4);
  final travel = path.total *
      (close == 0
          ? 1.0
          : close == 1
              ? 1 + g.u(0.01, 0.08)
              : close == 2
                  ? 1 - g.u(0.01, 0.06)
                  : 1 + g.u(-0.02, 0.02));
  final pts = _Sampler(Random(seed + 7))
      .stroke(path, startS, travel, scale: sz, reverse: reverse);
  var minx = double.infinity, maxx = -double.infinity;
  var miny = double.infinity, maxy = -double.infinity;
  for (final p in ideal) {
    minx = min(minx, p.dx);
    maxx = max(maxx, p.dx);
    miny = min(miny, p.dy);
    maxy = max(maxy, p.dy);
  }
  return Variant(cls, pts, ideal, max(maxx - minx, maxy - miny),
      'sz=${sz.round()} rot=${(th * 180 / pi).round()} round=${round.toStringAsFixed(2)} close=$close $tag');
}

Variant _openStroke(String cls, int seed, List<Offset> unit,
    {double? size, double? rot, String tag = ''}) {
  final g = _Sampler(Random(seed));
  final sz = size ?? g.logU(40, 700);
  final c = _centre(g);
  final th = rot ?? g.u(0, 2 * pi);
  final pts0 = _xf(unit, 1, 1, th, sz, c);
  final path = _Path(pts0);
  final pts = _Sampler(Random(seed + 7))
      .stroke(path, 0, path.total, scale: sz, closed: false);
  var minx = double.infinity, maxx = -double.infinity;
  var miny = double.infinity, maxy = -double.infinity;
  for (final p in pts0) {
    minx = min(minx, p.dx);
    maxx = max(maxx, p.dx);
    miny = min(miny, p.dy);
    maxy = max(maxy, p.dy);
  }
  return Variant(cls, pts, cls == 'line' ? pts0 : const [],
      max(maxx - minx, maxy - miny), 'sz=${sz.round()} rot=${(th * 180 / pi).round()} $tag');
}

List<Offset> _poly(List<List<double>> v) =>
    [for (final p in [...v, v.first]) Offset(p[0], p[1])];

List<Offset> _ellipse() => [
      for (var i = 0; i <= 180; i++)
        Offset(0.5 * cos(2 * pi * i / 180), 0.5 * sin(2 * pi * i / 180))
    ];

double _deg(double d) => d * pi / 180;

/// All figure generators: name -> (acceptable recognised types, generator).
final Map<String, _Gen> _gens = {
  'square': (s) {
    final g = _Sampler(Random(s));
    final a = g.u(0.94, 1.06);
    return _closed('square', s, _poly([[-.5, -.5], [.5, -.5], [.5, .5], [-.5, .5]]),
        sy: a, round: g.r.nextBool() ? g.u(0, 0.3) : 0);
  },
  'square45': (s) {
    final g = _Sampler(Random(s));
    return _closed('square45', s, _poly([[-.5, -.5], [.5, -.5], [.5, .5], [-.5, .5]]),
        sy: g.u(0.94, 1.06),
        rot: _deg(45 + g.u(-6, 6) + 90.0 * g.r.nextInt(4)),
        round: g.r.nextBool() ? g.u(0, 0.3) : 0);
  },
  'rhombus': (s) {
    final g = _Sampler(Random(s));
    final ratio = g.u(0.5, 0.75); // short/long diagonal
    final rot = g.r.nextBool()
        ? _deg(g.u(-8, 8) + 90.0 * g.r.nextInt(2))
        : null; // half near-upright diamonds, half random rotation
    return _closed('rhombus', s, _poly([[0, -.5], [.5 * ratio, 0], [0, .5], [-.5 * ratio, 0]]),
        rot: rot, round: g.r.nextBool() ? g.u(0, 0.2) : 0);
  },
  'rect_wide': (s) {
    final g = _Sampler(Random(s));
    return _closed('rect_wide', s, _poly([[-.5, -.5], [.5, -.5], [.5, .5], [-.5, .5]]),
        sy: 1 / g.u(1.4, 3.5),
        rot: g.r.nextBool() ? _deg(g.u(-6, 6)) : null,
        round: g.r.nextBool() ? g.u(0, 0.25) : 0);
  },
  'rect_tall': (s) {
    final g = _Sampler(Random(s));
    return _closed('rect_tall', s, _poly([[-.5, -.5], [.5, -.5], [.5, .5], [-.5, .5]]),
        sx: 1 / g.u(1.4, 3.5),
        rot: g.r.nextBool() ? _deg(g.u(-6, 6)) : null,
        round: g.r.nextBool() ? g.u(0, 0.25) : 0);
  },
  'tri_equi': (s) {
    final g = _Sampler(Random(s));
    final h = sqrt(3) / 2;
    return _closed('tri_equi', s, _poly([[0, -h / 1.5], [.5, h / 3], [-.5, h / 3]]),
        sy: g.u(0.9, 1.1), round: g.r.nextBool() ? g.u(0, 0.2) : 0);
  },
  'tri_right': (s) {
    final g = _Sampler(Random(s));
    return _closed('tri_right', s, _poly([[-.5, -.5], [-.5, .5], [.5, .5]]),
        sy: g.u(0.6, 1.2), round: g.r.nextBool() ? g.u(0, 0.15) : 0);
  },
  'tri_obtuse': (s) {
    final g = _Sampler(Random(s));
    final off = g.u(0.7, 1.2); // apex pushed beyond the base end
    return _closed('tri_obtuse', s, _poly([[-.5, 0.3], [.5, 0.3], [-.5 + off, -.15]]),
        round: g.r.nextBool() ? g.u(0, 0.12) : 0);
  },
  'circle': (s) {
    final g = _Sampler(Random(s));
    return _closed('circle', s, _ellipse(),
        sy: g.u(0.92, 1.08), smooth: true);
  },
  'ellipse': (s) {
    final g = _Sampler(Random(s));
    return _closed('ellipse', s, _ellipse(),
        sy: g.u(0.58, 0.8), smooth: true);
  },
  'line': (s) {
    final g = _Sampler(Random(s));
    final bow = g.u(0, 0.06);
    return _openStroke('line', s, [
      for (var i = 0; i <= 30; i++)
        Offset(i / 30 - .5, bow * sin(pi * i / 30))
    ], size: g.logU(30, 800));
  },
  'neg_scribble': (s) {
    final g = _Sampler(Random(s));
    final pts = <Offset>[const Offset(0, 0)];
    for (var i = 0; i < 18; i++) {
      pts.add(pts.last + Offset(g.u(-.35, .35), g.u(-.35, .35)));
    }
    return _openStroke('neg_scribble', s, pts);
  },
  'neg_scurve': (s) {
    final g = _Sampler(Random(s));
    final amp = g.u(0.25, 0.5);
    return _openStroke('neg_scurve', s, [
      for (var i = 0; i <= 60; i++)
        Offset(amp * sin(2 * pi * i / 60), i / 60 - .5)
    ]);
  },
  'neg_wave': (s) {
    final g = _Sampler(Random(s));
    final cycles = g.u(2, 4);
    return _openStroke('neg_wave', s, [
      for (var i = 0; i <= 90; i++)
        Offset(i / 90 - .5, 0.12 * sin(2 * pi * cycles * i / 90))
    ]);
  },
  'neg_spiral': (s) {
    final g = _Sampler(Random(s));
    final turns = g.u(1.8, 3.2);
    return _openStroke('neg_spiral', s, [
      for (var i = 0; i <= 160; i++)
        Offset(0.5 * (i / 160) * cos(2 * pi * turns * i / 160),
            0.5 * (i / 160) * sin(2 * pi * turns * i / 160))
    ]);
  },
  'neg_D': (s) {
    // closed D: straight spine + semicircle bulge
    final g = _Sampler(Random(s));
    final bulge = g.u(0.8, 1.0);
    final unit = <Offset>[const Offset(-.25, -.5)];
    for (var i = 0; i <= 24; i++) {
      final a = -pi / 2 + pi * i / 24;
      unit.add(Offset(-.25 + .5 * bulge * cos(a) + 0.0, .5 * sin(a)));
    }
    unit.add(const Offset(-.25, -.5));
    return _closed('neg_D', s, unit);
  },
  'neg_halfcircle': (s) {
    return _openStroke('neg_halfcircle', s, [
      for (var i = 0; i <= 40; i++)
        Offset(.5 * cos(pi * i / 40), -.5 * sin(pi * i / 40))
    ]);
  },
  'neg_U': (s) =>
      _openStroke('neg_U', s,
          [const Offset(-.5, -.5), const Offset(-.5, .5), const Offset(.5, .5), const Offset(.5, -.5)]),
  'neg_Z': (s) => _openStroke('neg_Z', s,
      [const Offset(-.5, -.5), const Offset(.5, -.5), const Offset(-.5, .5), const Offset(.5, .5)]),
  'neg_V': (s) => _openStroke(
      'neg_V', s, [const Offset(-.5, -.5), const Offset(0, .5), const Offset(.5, -.5)]),
};

/// What each expected figure may be recognised as.
const Map<String, Set<String>> _accept = {
  'square': {'rectangle', 'rhombus'},
  'square45': {'rectangle', 'rhombus'},
  'rhombus': {'rhombus'},
  'rect_wide': {'rectangle'},
  'rect_tall': {'rectangle'},
  'tri_equi': {'triangle'},
  'tri_right': {'triangle'},
  'tri_obtuse': {'triangle'},
  'circle': {'circle'},
  'ellipse': {'circle'},
  'line': {'line'},
};

const _cols = ['line', 'circle', 'rectangle', 'rhombus', 'triangle', 'none'];

String _label(ShapeData? s) => s?.shapeType ?? 'none';

({Map<String, Map<String, int>> matrix, Map<String, int> geom, Map<String, int> total, int degenerate})
    runAll(int perClass, {void Function(String)? log}) {
  final matrix = <String, Map<String, int>>{};
  final geom = <String, int>{};
  final total = <String, int>{};
  var degenerate = 0;
  for (final e in _gens.entries) {
    final row = matrix[e.key] = {for (final c in _cols) c: 0};
    for (var i = 0; i < perClass; i++) {
      final seed = 1000 + i * 17 + e.key.codeUnits.fold<int>(0, (a, c) => a * 31 + c) % 997;
      final v = e.value(seed);
      final res = recognizeShape(v.points, color: 0xFF000000, strokeWidth: 2);
      final lab = _label(res);
      row[lab] = row[lab]! + 1;
      total[e.key] = (total[e.key] ?? 0) + 1;
      if (res != null) {
        final w = (res.x2 - res.x1).abs(), h = (res.y2 - res.y1).abs();
        final tiny = res.shapeType != 'line' && (w < 1 || h < 1);
        if (!_finite(res) || tiny) {
          degenerate++;
          log?.call('DEGENERATE ${e.key} #$i ${v.tag}: $lab $res');
        }
        final ok = _accept[e.key]?.contains(lab) ?? false;
        if (ok && v.ideal.isNotEmpty) {
          final err = _outlineError(outlineOf(res), v.ideal, v.scale);
          if (err > 0.06) {
            geom[e.key] = (geom[e.key] ?? 0) + 1;
            log?.call('GEOM ${e.key} #$i err=${err.toStringAsFixed(3)} ${v.tag}');
          }
        }
      }
      final want = _accept[e.key] ?? {'none'};
      if (!want.contains(lab)) {
        log?.call('MISS ${e.key} #$i -> $lab ${v.tag}');
      }
    }
  }
  return (matrix: matrix, geom: geom, total: total, degenerate: degenerate);
}

String formatMatrix(Map<String, Map<String, int>> m, Map<String, int> geom) {
  final b = StringBuffer();
  b.writeln('${'expected'.padRight(15)}${_cols.map((c) => c.padLeft(10)).join()}   ok%  geom-off');
  for (final e in m.entries) {
    final want = _accept[e.key] ?? {'none'};
    final n = e.value.values.fold<int>(0, (a, c) => a + c);
    final ok = e.value.entries.where((x) => want.contains(x.key)).fold<int>(0, (a, c) => a + c.value);
    b.writeln('${e.key.padRight(15)}${_cols.map((c) => e.value[c].toString().padLeft(10)).join()}'
        '${(100 * ok / n).round().toString().padLeft(6)}${(geom[e.key] ?? 0).toString().padLeft(9)}');
  }
  return b.toString();
}

void main() {
  test('confusion matrix over synthesised hand-drawn variants', () {
    final lines = <String>[];
    final r = runAll(const int.fromEnvironment('N', defaultValue: 40), log: lines.add);
    // ignore: avoid_print
    print(lines.join('\n'));
    // ignore: avoid_print
    print(formatMatrix(r.matrix, r.geom));
    expect(r.degenerate, 0, reason: 'no NaN / zero-size output');
    for (final e in r.matrix.entries) {
      final want = _accept[e.key] ?? {'none'};
      final n = e.value.values.fold<int>(0, (a, c) => a + c);
      final ok = e.value.entries
          .where((x) => want.contains(x.key))
          .fold<int>(0, (a, c) => a + c.value);
      // neg_D is a rounded rectangle half-way: tolerate more confusion there
      final min = e.key == 'neg_D' ? 0.85 : 0.95;
      expect(ok / n, greaterThanOrEqualTo(min), reason: e.key);
      expect((r.geom[e.key] ?? 0) / n, lessThanOrEqualTo(0.05),
          reason: '${e.key}: recognised with the wrong geometry');
    }
    // A square is never read as a circle or a triangle.
    for (final k in ['square', 'square45']) {
      expect(r.matrix[k]!['circle']! + r.matrix[k]!['triangle']!, 0, reason: k);
    }
  });
}
