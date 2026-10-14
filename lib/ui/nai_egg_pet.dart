import 'dart:async';
import 'dart:math' as math;

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

class NaiEggSprite extends StatelessWidget {
  const NaiEggSprite({super.key, required this.frame, this.size = 88});
  final int frame;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment(frame - 1.0, 0),
        minWidth: size * 3,
        maxWidth: size * 3,
        minHeight: size,
        maxHeight: size,
        child: Image.asset(
          'assets/nai-family/egg-talk-sheet.webp',
          width: size * 3,
          height: size,
          fit: BoxFit.fill,
          cacheWidth: (size * 3 * MediaQuery.devicePixelRatioOf(context))
              .ceil(),
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

/// Overlay hit-tests only the egg while docked. The rest of the app remains
/// interactive. A backdrop is added only while the quick menu is open.
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
    with TickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );
  late final sway = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  Timer? idlePause;
  bool expanded = false;
  bool openingMotion = false;
  ({double reveal, double lift, double tilt}) fromPose = (
    reveal: 0,
    lift: 0,
    tilt: -.38,
  );
  double closingMenuOpacity = 0;
  double anchorFraction = .62;

  @override
  void initState() {
    super.initState();
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed && expanded) gentleSway();
    });
    sway.addStatusListener((status) {
      if (status == AnimationStatus.completed && expanded) {
        idlePause = Timer(const Duration(seconds: 5), gentleSway);
      }
    });
  }

  void gentleSway() {
    if (!mounted || !expanded || MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    sway.forward(from: 0);
  }

  double get menuOpacity => openingMotion
      ? ((animation.value - .75) / .25).clamp(0.0, 1.0)
      : closingMenuOpacity *
            (1 -
                Curves.easeOut.transform(
                  (animation.value / .55).clamp(0.0, 1.0),
                ));

  ({double reveal, double lift, double tilt}) get pose {
    final progress = openingMotion
        ? Curves.easeOutCubic.transform((animation.value / .7).clamp(0.0, 1.0))
        : Curves.easeInOutCubic.transform(animation.value);
    double between(double start, double end) =>
        start + (end - start) * progress;
    return (
      reveal: between(fromPose.reveal, openingMotion ? 1 : 0),
      lift:
          between(fromPose.lift, openingMotion ? -26 : 0) -
          (openingMotion ? 4 * math.sin(math.pi * progress) : 0),
      tilt:
          between(fromPose.tilt, openingMotion ? 0 : -.38) +
          (expanded ? .009 * math.sin(sway.value * math.pi * 2) : 0),
    );
  }

  void transition(bool open) {
    // Capture the visible pose before changing direction so a quick second tap
    // returns smoothly from the current position instead of snapping to an end.
    final current = pose;
    final opacity = menuOpacity;
    idlePause?.cancel();
    sway.stop();
    sway.value = 0;
    setState(() {
      fromPose = current;
      closingMenuOpacity = opacity;
      openingMotion = open;
      expanded = open;
    });
    widget.onExpansionChanged?.call(open);
    animation.duration = Duration(milliseconds: open ? 560 : 360);
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
    transition(true);
  }

  void dismiss() {
    if (!mounted || !expanded) return;
    transition(false);
  }

  void choose(int index) {
    dismiss();
    widget.onSelect(index);
  }

  int mouthFrame(double t) {
    if (!expanded || t < .2 || t >= .72) return 0;
    // One closed → 安 → 迪 → closed mouth movement on entry only.
    return t < .52 ? 1 : 2;
  }

  @override
  void dispose() {
    idlePause?.cancel();
    if (expanded) widget.onExpansionChanged?.call(false);
    animation.dispose();
    sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const size = 88.0, menuWidth = 160.0;
      final padding = MediaQuery.paddingOf(context);
      final topLimit = padding.top + 12;
      final bottomLimit = box.maxHeight - padding.bottom - 80;
      final available = math.max(44.0, bottomLimit - topLimit);
      final menuHeight = math.min(236.0, available);
      final anchor = (box.maxHeight * anchorFraction - size / 2).clamp(
        topLimit,
        math.max(topLimit, bottomLimit - size),
      );
      final openX = math.max(0.0, box.maxWidth - size - 16);
      final menuX = math.max(8.0, openX - menuWidth - 12);
      final menuY = (anchor - 26 + size / 2 - menuHeight / 2)
          .clamp(topLimit, math.max(topLimit, bottomLimit - menuHeight))
          .toDouble();
      return AnimatedBuilder(
        animation: Listenable.merge([animation, sway]),
        builder: (context, _) {
          final t = animation.value;
          final current = pose;
          final x = box.maxWidth - size / 2 - (size / 2 + 16) * current.reveal;
          final y = anchor + current.lift;
          final opacity = menuOpacity;
          final visible = expanded || animation.isAnimating;
          return BlockSemantics(
            blocking: expanded,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (visible)
                  Positioned.fill(
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
                              alpha: .05 * current.reveal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (opacity > 0)
                  Positioned(
                    left: menuX,
                    top: menuY,
                    width: menuWidth,
                    height: menuHeight,
                    child: IgnorePointer(
                      ignoring: !expanded,
                      child: Opacity(
                        opacity: opacity,
                        child: Material(
                          key: const ValueKey('nai-pet-menu'),
                          color: context.meike.surface,
                          elevation: 8,
                          shadowColor: context.meike.ink.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var i = 0; i < 5; i++)
                                    SizedBox(
                                      height: 44,
                                      child: InkWell(
                                        key: ValueKey('nai-pet-destination-$i'),
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => choose(i),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              NaiCharacter(
                                                NaiAnimal.values[i],
                                                size: 28,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  const [
                                                    '课表',
                                                    '今天',
                                                    '讨论',
                                                    '校园',
                                                    '我的',
                                                  ][i],
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: context.meike.ink,
                                                  ),
                                                ),
                                              ),
                                            ],
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
                    ),
                  ),
                Positioned(
                  left: x,
                  top: y,
                  width: size,
                  height: size,
                  child: Semantics(
                    button: true,
                    label: expanded ? '奶蛋宠物，点击收起快捷导航' : '奶蛋宠物，点击展开快捷导航',
                    child: GestureDetector(
                      key: const ValueKey('nai-pet-egg'),
                      behavior: HitTestBehavior.opaque,
                      onTap: reveal,
                      onVerticalDragUpdate: expanded
                          ? null
                          : (details) => setState(() {
                              anchorFraction =
                                  (anchorFraction +
                                          details.delta.dy / box.maxHeight)
                                      .clamp(.05, .95);
                            }),
                      child: Transform.rotate(
                        angle: current.tilt,
                        child: NaiEggSprite(frame: mouthFrame(t), size: size),
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
