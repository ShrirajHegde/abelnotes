import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Spring from damping ratio (1 = no overshoot) and response in seconds.
/// Rationale and the per-interaction values: lib/ui/theme/README.md.
SpringDescription hwSpring({double damping = 1, double response = 0.3}) {
  final w = 2 * math.pi / response;
  return SpringDescription(mass: 1, stiffness: w * w, damping: 2 * damping * w);
}

class HwSprings {
  static final standard = hwSpring();
  static final press = hwSpring(response: 0.15);
  static final popup = hwSpring(response: 0.28);
  static final open = hwSpring(response: 0.45);
  /// Only after a gesture carried momentum (flick, throw).
  static final fling = hwSpring(damping: 0.8, response: 0.35);
}

/// Where a flick at [velocity] px/s comes to rest (scroll-like decay).
double hwProject(double velocity, {double decelerationRate = 0.998}) =>
    velocity / 1000 * decelerationRate / (1 - decelerationRate);

/// Progressive resistance for [overshoot] px past a boundary.
double hwRubberband(double overshoot, double dimension, {double c = 0.55}) =>
    overshoot * dimension * c / (dimension + c * overshoot.abs());

bool hwReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

extension HwSpringTo on AnimationController {
  /// Spring from the live value, keeping the current velocity unless given.
  TickerFuture springTo(double target,
      {SpringDescription? spring, double? velocity, bool instant = false}) {
    if (instant) {
      value = target;
      return TickerFuture.complete();
    }
    return animateWith(SpringSimulation(
      spring ?? HwSprings.standard,
      value,
      target,
      velocity ?? this.velocity,
      tolerance: const Tolerance(distance: 0.001, velocity: 0.01),
    ));
  }
}
