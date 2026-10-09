import 'package:flutter/material.dart';

/// [showModalBottomSheet] that scrolls when its content outgrows the window
/// (default sheets are capped at 9/16 of the height and clip the rest).
Future<T?> showScrollableSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: backgroundColor,
    shape: shape,
    builder: (ctx) => SingleChildScrollView(child: builder(ctx)),
  );
}
