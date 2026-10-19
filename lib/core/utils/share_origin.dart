import 'package:flutter/widgets.dart';

/// Where the share sheet's popover points on iPad: the rect of the widget
/// at [context] (the share button), in global coordinates. iPad requires
/// one (share_plus fails without it); phones ignore it. Null when that
/// widget isn't laid out.
Rect? shareOriginOf(BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
