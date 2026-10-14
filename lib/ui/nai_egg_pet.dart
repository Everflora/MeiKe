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
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
    reverseDuration: const Duration(milliseconds: 220),
  );
  bool expanded = false;
  double anchorFraction = .62;
  void reveal() {
    if (expanded) {
      dismiss();
      return;
    }
    setState(() => expanded = true);
    widget.onExpansionChanged?.call(true);
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.value = 1;
    } else {
      animation.forward(from: 0);
    }
  }

  void dismiss() {
    if (!mounted || !expanded) return;
    setState(() => expanded = false);
    widget.onExpansionChanged?.call(false);
    if (MediaQuery.disableAnimationsOf(context)) {
      animation.value = 0;
    } else {
      animation.reverse();
    }
  }

  void choose(int index) {
    dismiss();
    widget.onSelect(index);
  }

  int mouthFrame(double t) {
    if (!expanded || t < .15 || t >= .85) return 0;
    // Two complete closed → 安 → 迪 → closed cycles, then show the menu.
    final phase = ((t - .15) / .7 * 2) % 1;
    return phase < .1 || phase >= .9
        ? 0
        : phase < .5
        ? 1
        : 2;
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
        animation: animation,
        builder: (context, _) {
          final t = animation.value;
          final spring = Curves.elasticOut.transform((t / .65).clamp(0.0, 1.0));
          final x = box.maxWidth - size / 2 - (size / 2 + 16) * spring;
          final y =
              anchor -
              26 * spring -
              12 * math.sin(math.pi * (t / .65).clamp(0.0, 1.0));
          final wobble = math.sin(t * math.pi * 6) * (1 - t) * .09;
          final ready = expanded && t >= .88;
          return BlockSemantics(
            blocking: expanded,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (expanded)
                  Positioned.fill(
                    child: Semantics(
                      button: true,
                      label: '收起奶蛋菜单',
                      child: GestureDetector(
                        key: const ValueKey('nai-pet-dismiss'),
                        behavior: HitTestBehavior.opaque,
                        onTap: dismiss,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: .05),
                        ),
                      ),
                    ),
                  ),
                if (ready)
                  Positioned(
                    left: menuX,
                    top: menuY,
                    width: menuWidth,
                    height: menuHeight,
                    child: Opacity(
                      opacity: ((t - .88) / .12).clamp(0.0, 1.0),
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
                                                overflow: TextOverflow.ellipsis,
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
                        angle: -.38 * (1 - spring),
                        child: Transform.scale(
                          scaleX: 1 + wobble,
                          scaleY: 1 - wobble,
                          child: NaiEggSprite(frame: mouthFrame(t), size: size),
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
