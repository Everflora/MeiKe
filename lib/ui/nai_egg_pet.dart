import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'nai_family.dart';
import 'theme.dart';

class NaiRouteTracker extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  Route<dynamic>? get current => routes.lastOrNull;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute == null) return;
    final index = routes.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) routes[index] = newRoute;
  }
}

/// A single, stationary body texture. Only the mouth path changes each display
/// frame; swapping full-body sprites made the silhouette and eyes visibly jump.
class NaiEggSprite extends StatelessWidget {
  const NaiEggSprite({super.key, this.mouthProgress = 0, this.size = 88});
  final double mouthProgress, size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      foregroundPainter: _EggMouth(mouthProgress),
      child: Image.asset(
        'assets/nai-family/egg-neutral-body.webp',
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        excludeFromSemantics: true,
      ),
    ),
  );
}

class _EggMouth extends CustomPainter {
  _EggMouth(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    // The neutral plate is 1116 × 1409. Keep the mouth registered to the same
    // face coordinates as the body even if the pet is resized in landscape.
    final fitted = applyBoxFit(
      BoxFit.contain,
      const Size(1116, 1409),
      size,
    ).destination;
    final image = Alignment.center.inscribe(fitted, Offset.zero & size);
    final center = Offset(image.center.dx, image.top + image.height * .336);
    final p = progress.clamp(0.0, 1.0);
    double blend(double a, double b, double t) =>
        a + (b - a) * Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final double openness, widthFactor;
    if (p <= .32) {
      openness = blend(0, 1, p / .32);
      widthFactor = blend(.185, .115, p / .32);
    } else if (p <= .68) {
      openness = blend(1, .38, (p - .32) / .36);
      widthFactor = blend(.115, .17, (p - .32) / .36);
    } else {
      openness = blend(.38, 0, (p - .68) / .32);
      widthFactor = blend(.17, .185, (p - .68) / .32);
    }
    final width = image.width * widthFactor;
    final height = image.height * (.0025 + .052 * openness);
    final path = Path()
      ..moveTo(center.dx - width / 2, center.dy)
      ..cubicTo(
        center.dx - width * .28,
        center.dy - height * .62,
        center.dx + width * .28,
        center.dy - height * .62,
        center.dx + width / 2,
        center.dy,
      )
      ..cubicTo(
        center.dx + width * .28,
        center.dy + height,
        center.dx - width * .28,
        center.dy + height,
        center.dx - width / 2,
        center.dy,
      )
      ..close();
    canvas.drawPath(
      path.shift(Offset(0, image.height * .004)),
      Paint()
        ..color = const Color(0xFF79521B).withValues(alpha: .28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, image.height * .005),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader =
            const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF38200E), Color(0xFF66351F)],
            ).createShader(
              Rect.fromCenter(center: center, width: width, height: height * 2),
            ),
    );
    if (openness > .08) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(0, height * .72),
          width: width * .65,
          height: height * .45,
        ),
        Paint()
          ..color = const Color(
            0xFFB88377,
          ).withValues(alpha: openness.clamp(0.0, 1.0)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_EggMouth oldDelegate) => oldDelegate.progress != progress;
}

typedef _EggPose = ({Offset center, double tilt});

class _PetGeometry {
  _PetGeometry(this.viewport, EdgeInsets padding) {
    bounds = Rect.fromLTRB(
      12,
      padding.top + 12,
      viewport.width - 12,
      math.max(padding.top + 100, viewport.height - padding.bottom - 80),
    );
    extent = math.min(124.0, bounds.shortestSide / 2 - 4);
    bubbleSize = (extent * .52).clamp(44.0, 64.0);
    radius = extent - bubbleSize / 2;
    eggSize = ((radius - bubbleSize / 2 - 8) * 2).clamp(40.0, 88.0);
  }
  final Size viewport;
  late final Rect bounds;
  late final double extent, bubbleSize, radius, eggSize;
  _EggPose dock(bool left, double fraction) => (
    center: Offset(
      left ? 0 : viewport.width,
      (viewport.height * fraction).clamp(
        bounds.top + eggSize / 2,
        bounds.bottom - eggSize / 2,
      ),
    ),
    tilt: left ? .38 : -.38,
  );
  _EggPose open(bool left, double fraction) => (
    center: Offset(
      left ? bounds.left + extent : bounds.right - extent,
      (dock(left, fraction).center.dy - 26).clamp(
        bounds.top + extent,
        bounds.bottom - extent,
      ),
    ),
    tilt: 0,
  );
  Offset dragPoint(Offset point) => Offset(
    point.dx.clamp(0.0, viewport.width),
    point.dy.clamp(bounds.top + eggSize / 2, bounds.bottom - eggSize / 2),
  );
}

/// Hit-tests only the pet while docked. Five independent circular destinations
/// surround the pet; the background is blocked only while the menu is open.
class NaiEggCompanion extends StatefulWidget {
  const NaiEggCompanion({
    super.key,
    required this.onSelect,
    this.onExpansionChanged,
  });
  final ValueChanged<int> onSelect;
  final ValueChanged<bool>? onExpansionChanged;
  @override
  NaiEggCompanionState createState() => NaiEggCompanionState();
}

class NaiEggCompanionState extends State<NaiEggCompanion>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );
  late _PetGeometry _geometry;
  _EggPose? _fromPose, _targetPose;
  _EggPose? _dragOrigin;
  Offset? dragCenter, lastPointer;
  bool expanded = false, entrySequence = false, dockLeft = false;
  bool dragging = false, dragWasExpanded = false;
  double anchorFraction = .62, menuFromOpacity = 0, mouthFromProgress = 0;
  Offset? menuCenter;

  _EggPose get _pose {
    if (dragging) return (center: dragCenter!, tilt: _dragOrigin!.tilt);
    final dock = _geometry.dock(dockLeft, anchorFraction);
    final start = _fromPose ?? dock;
    final target = _targetPose ?? dock;
    final t = entrySequence
        ? Curves.easeOutCubic.transform((animation.value / .36).clamp(0.0, 1.0))
        : Curves.easeInOutCubic.transform(animation.value);
    return (
      center: Offset.lerp(start.center, target.center, t)!,
      tilt: start.tilt + (target.tilt - start.tilt) * t,
    );
  }

  double get mouthProgress {
    if (dragging) return 0;
    if (entrySequence && expanded) {
      // Land at 396 ms, stay still, then speak from 473 to 968 ms.
      final p = ((animation.value - .43) / .45).clamp(0.0, 1.0);
      return p >= 1 ? 0 : p;
    }
    if (mouthFromProgress <= 0 || animation.value >= 1) return 0;
    return mouthFromProgress +
        (1 - mouthFromProgress) * Curves.easeOut.transform(animation.value);
  }

  double get menuOpacity {
    if (dragging) return 0;
    if (entrySequence && expanded) {
      return ((animation.value - .9) / .1).clamp(0.0, 1.0);
    }
    return expanded
        ? menuFromOpacity +
              (1 - menuFromOpacity) * Curves.easeOut.transform(animation.value)
        : menuFromOpacity *
              (1 -
                  Curves.easeOut.transform(
                    (animation.value / .55).clamp(0.0, 1.0),
                  ));
  }

  void _animateTo(_EggPose target, {required bool open, bool speak = false}) {
    final current = _pose, opacity = menuOpacity, mouth = mouthProgress;
    animation.stop();
    setState(() {
      _fromPose = current;
      _targetPose = target;
      dragging = false;
      entrySequence = speak;
      menuFromOpacity = opacity;
      mouthFromProgress = mouth;
      expanded = open;
      if (open) menuCenter = target.center;
    });
    widget.onExpansionChanged?.call(open);
    animation.duration = Duration(milliseconds: speak ? 1100 : 360);
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.value = 1;
    } else {
      animation.forward(from: 0);
    }
  }

  void reveal() {
    if (expanded) {
      dismiss();
      return;
    }
    _animateTo(
      _geometry.open(dockLeft, anchorFraction),
      open: true,
      speak: true,
    );
  }

  void dismiss() {
    if (!mounted || !expanded) return;
    _animateTo(_geometry.dock(dockLeft, anchorFraction), open: false);
  }

  void choose(int index) {
    dismiss();
    widget.onSelect(index);
  }

  Offset _pointer(Offset global) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(global);
  void _dragStart(DragStartDetails details) {
    final current = _pose;
    animation.stop();
    dragWasExpanded = expanded;
    if (expanded) widget.onExpansionChanged?.call(false);
    setState(() {
      _dragOrigin = current;
      dragCenter = current.center;
      lastPointer = _pointer(details.globalPosition);
      dragging = true;
      expanded = false;
    });
  }

  void _dragUpdate(DragUpdateDetails details) => setState(() {
    dragCenter = _geometry.dragPoint(dragCenter! + details.delta);
    lastPointer = _pointer(details.globalPosition);
  });
  void _dragEnd({bool cancelled = false}) {
    if (!dragging || _dragOrigin == null) return;
    final x = lastPointer!.dx;
    if (!cancelled && (x <= 48 || x >= _geometry.viewport.width - 48)) {
      dockLeft = x <= 48;
      anchorFraction = dragCenter!.dy / _geometry.viewport.height;
      _animateTo(_geometry.dock(dockLeft, anchorFraction), open: false);
    } else {
      _animateTo(_dragOrigin!, open: dragWasExpanded);
    }
  }

  @override
  void dispose() {
    if (expanded) widget.onExpansionChanged?.call(false);
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final next = _PetGeometry(box.biggest, MediaQuery.paddingOf(context));
      // Rotation or window resizing recomputes a completed destination without
      // retaining off-screen coordinates from the previous viewport.
      if (_fromPose != null &&
          !animation.isAnimating &&
          !dragging &&
          (_geometry.viewport != next.viewport ||
              _geometry.bounds != next.bounds)) {
        _targetPose = expanded
            ? next.open(dockLeft, anchorFraction)
            : next.dock(dockLeft, anchorFraction);
        menuCenter = _targetPose!.center;
      }
      _geometry = next;
      return AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final current = _pose, opacity = menuOpacity;
          final visible = expanded || animation.isAnimating;
          final size = _geometry.eggSize;
          final palette = context.meike;
          final bubbleColor = Color.lerp(palette.paper, palette.soft, .35)!;
          return BlockSemantics(
            blocking: expanded,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (visible)
                  Positioned.fill(
                    key: const ValueKey('nai-pet-backdrop-position'),
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: Semantics(
                        button: true,
                        label: '收起奶蛋菜单',
                        child: GestureDetector(
                          key: const ValueKey('nai-pet-dismiss'),
                          behavior: HitTestBehavior.opaque,
                          onTap: dismiss,
                          child: ColoredBox(
                            color: Colors.black.withValues(
                              alpha: .04 * opacity,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (opacity > 0)
                  Positioned.fill(
                    key: const ValueKey('nai-pet-menu-position'),
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: ExcludeSemantics(
                        excluding: !expanded,
                        child: Opacity(
                          opacity: opacity,
                          child: Stack(
                            key: const ValueKey('nai-pet-menu'),
                            children: [
                              for (var i = 0; i < 5; i++)
                                Positioned(
                                  left:
                                      menuCenter!.dx +
                                      _geometry.radius *
                                          math.cos(
                                            -math.pi / 2 + i * math.pi * 2 / 5,
                                          ) -
                                      _geometry.bubbleSize / 2,
                                  top:
                                      menuCenter!.dy +
                                      _geometry.radius *
                                          math.sin(
                                            -math.pi / 2 + i * math.pi * 2 / 5,
                                          ) -
                                      _geometry.bubbleSize / 2,
                                  width: _geometry.bubbleSize,
                                  height: _geometry.bubbleSize,
                                  child: Material(
                                    key: ValueKey('nai-pet-bubble-$i'),
                                    color: bubbleColor,
                                    elevation: 3,
                                    shadowColor: palette.ink.withValues(
                                      alpha: .12,
                                    ),
                                    shape: CircleBorder(
                                      side: BorderSide(color: palette.line),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: ValueKey('nai-pet-destination-$i'),
                                      customBorder: const CircleBorder(),
                                      onTap: () => choose(i),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              NaiCharacter(
                                                NaiAnimal.values[i],
                                                size: 24,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                const [
                                                  '课表',
                                                  '今天',
                                                  '讨论',
                                                  '校园',
                                                  '我的',
                                                ][i],
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: palette.ink,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  key: const ValueKey('nai-pet-position'),
                  left: current.center.dx - size / 2,
                  top: current.center.dy - size / 2,
                  width: size,
                  height: size,
                  child: Semantics(
                    button: true,
                    label: expanded
                        ? '奶蛋宠物，点击收起快捷导航'
                        : '奶蛋宠物，点击展开快捷导航，拖到左右边缘可吸附',
                    child: GestureDetector(
                      key: const ValueKey('nai-pet-egg'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onTap: reveal,
                      onPanStart: _dragStart,
                      onPanUpdate: _dragUpdate,
                      onPanEnd: (_) => _dragEnd(),
                      onPanCancel: () => _dragEnd(cancelled: true),
                      child: Transform.rotate(
                        angle: current.tilt,
                        child: NaiEggSprite(
                          mouthProgress: mouthProgress,
                          size: size,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
