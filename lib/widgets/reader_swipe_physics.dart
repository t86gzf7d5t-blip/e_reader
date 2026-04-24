import 'package:flutter/widgets.dart';

/// Page physics tuned for touch-first reading surfaces.
///
/// The defaults can feel a bit stubborn on tablets because shorter flicks
/// often spring back to the current page. Lowering the fling thresholds makes
/// intentional swipes feel more responsive without removing page snapping.
class ReaderSwipePhysics extends PageScrollPhysics {
  const ReaderSwipePhysics({super.parent});

  @override
  ReaderSwipePhysics applyTo(ScrollPhysics? ancestor) {
    return ReaderSwipePhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 10.0;

  @override
  double get minFlingVelocity => 120.0;

  @override
  double? get dragStartDistanceMotionThreshold => 3.0;
}
