import 'package:flutter/material.dart';

import '../theme/hw_motion.dart';

/// Translates [child] to [offset] on springs (one per axis), always from
/// where it is on screen, so a retarget mid-flight never jumps.
class HwSpringOffset extends StatefulWidget {
  final Offset offset;
  final Widget child;
  final SpringDescription? spring;

  const HwSpringOffset({
    super.key,
    required this.offset,
    required this.child,
    this.spring,
  });

  @override
  State<HwSpringOffset> createState() => _HwSpringOffsetState();
}

class _HwSpringOffsetState extends State<HwSpringOffset>
    with TickerProviderStateMixin {
  late final AnimationController _x =
      AnimationController.unbounded(vsync: this, value: widget.offset.dx);
  late final AnimationController _y =
      AnimationController.unbounded(vsync: this, value: widget.offset.dy);

  @override
  void didUpdateWidget(HwSpringOffset old) {
    super.didUpdateWidget(old);
    if (old.offset == widget.offset) return;
    final instant = hwReduceMotion(context);
    _x.springTo(widget.offset.dx, spring: widget.spring, instant: instant);
    _y.springTo(widget.offset.dy, spring: widget.spring, instant: instant);
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_x, _y]),
        builder: (_, child) =>
            Transform.translate(offset: Offset(_x.value, _y.value), child: child),
        child: widget.child,
      );
}

/// Shows/hides [child] as a material arriving: scale, fade and blur move
/// together, growing out of [alignment] (point it at the trigger). Keeps
/// the last child on screen while it leaves.
class HwMaterialize extends StatefulWidget {
  final bool visible;
  final Alignment alignment;
  final Widget child;

  const HwMaterialize({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.center,
  });

  @override
  State<HwMaterialize> createState() => _HwMaterializeState();
}

class _HwMaterializeState extends State<HwMaterialize>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 0);
  late Widget _shown = widget.child;

  @override
  void initState() {
    super.initState();
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.springTo(1, spring: HwSprings.popup, instant: hwReduceMotion(context));
      });
    }
  }

  @override
  void didUpdateWidget(HwMaterialize old) {
    super.didUpdateWidget(old);
    if (widget.visible) _shown = widget.child;
    if (old.visible != widget.visible) {
      _c.springTo(widget.visible ? 1 : 0,
          spring: HwSprings.popup, instant: hwReduceMotion(context));
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value.clamp(0.0, 1.0);
        if (t <= 0.001 && !widget.visible) return const SizedBox.shrink();
        return IgnorePointer(
          ignoring: !widget.visible,
          child: Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.92 + 0.08 * _c.value,
              alignment: widget.alignment,
              child: child,
            ),
          ),
        );
      },
      child: _shown,
    );
  }
}
