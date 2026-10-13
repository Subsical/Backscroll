import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class RowExtents {
  final _known = <Object, (double, double)>{};
  double _plain = 0;

  bool get isEmpty => _known.isEmpty;

  double of(Object id, double extra) =>
      _known[id]?.$1 ?? _plain / _known.length + extra;

  void _record(Object id, double extent, double extra) {
    final plain = extent - extra;
    _plain += plain - (_known[id]?.$2 ?? 0);
    _known[id] = (extent, plain);
  }
}

// a lazy list guesses its length from the rows on screen, which makes the
// scrollbar jump as short and tall rows scroll past
class MeasuredRows extends SliverChildBuilderDelegate {
  MeasuredRows({
    required this.extents,
    required this.idOf,
    required IndexedWidgetBuilder builder,
    required int childCount,
    this.extraOf,
  }) : super(
         (context, index) => _Measured(
           extents: extents,
           id: idOf(index),
           extra: extraOf?.call(index) ?? 0,
           child: builder(context, index),
         ),
         childCount: childCount,
       );

  final RowExtents extents;
  final Object Function(int index) idOf;
  final double Function(int index)? extraOf;

  @override
  double? estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) {
    if (extents.isEmpty) return null;
    var end = trailingScrollOffset;
    for (var i = lastIndex + 1; i < childCount!; i++) {
      end += extents.of(idOf(i), extraOf?.call(i) ?? 0);
    }
    return end;
  }
}

class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({
    required this.extents,
    required this.id,
    required this.extra,
    super.child,
  });

  final RowExtents extents;
  final Object id;
  final double extra;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(extents, id, extra);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) {
    if (renderObject.id == id &&
        renderObject.extra == extra &&
        renderObject.extents == extents) {
      return;
    }
    renderObject
      ..extents = extents
      ..id = id
      ..extra = extra
      ..markNeedsLayout();
  }
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.extents, this.id, this.extra);

  RowExtents extents;
  Object id;
  double extra;

  @override
  void performLayout() {
    super.performLayout();
    extents._record(id, size.height, extra);
  }
}
