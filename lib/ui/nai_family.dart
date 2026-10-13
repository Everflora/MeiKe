import 'package:flutter/material.dart';

import 'appearance.dart';
import 'theme.dart';

enum NaiAnimal {
  frog('naiwa-front', '奶蛙'),
  chicken('naiji', '奶鸡'),
  mouse('naishu', '奶鼠'),
  dog('naigou', '奶狗'),
  egg('naidan', '奶蛋'),
  frogBack('naiwa-back', '奶蛙背面');

  const NaiAnimal(this.asset, this.label);
  final String asset, label;
}

extension NaiContext on BuildContext {
  bool get naiFamily => meike.design == MeikeTheme.naiFamily;
}

class NaiCharacter extends StatelessWidget {
  const NaiCharacter(this.animal, {super.key, this.size = 48});
  final NaiAnimal animal;
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/nai-family/${animal.asset}.webp',
    width: size,
    height: size,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );
}

class NaiWallpaper extends StatelessWidget {
  const NaiWallpaper({super.key});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Opacity(
        opacity: Theme.of(context).brightness == Brightness.dark ? .10 : .18,
        child: Image.asset(
          'assets/nai-family/family.webp',
          fit: BoxFit.contain,
          alignment: Alignment.center,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    ),
  );
}

class NaiFamilyBanner extends StatelessWidget {
  const NaiFamilyBanner({super.key, this.height = 120});
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: ColoredBox(
        color: context.meike.soft,
        child: Image.asset(
          'assets/nai-family/family.webp',
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

/// Uses actual rendered course rectangles, including overlapping lanes.
/// The fallback may cover a small portion of the preceding course as designed.
Rect naiEggPlacement(Rect course, List<Rect> occupied, Size bounds) {
  final side = course.width.clamp(28.0, 42.0);
  final candidates = [
    Rect.fromLTWH(
      course.center.dx - side / 2,
      course.top - side + 2,
      side,
      side,
    ),
    Rect.fromLTWH(
      course.left - side + 2,
      course.center.dy - side / 2,
      side,
      side,
    ),
    Rect.fromLTWH(course.right - 2, course.center.dy - side / 2, side, side),
    Rect.fromLTWH(course.center.dx - side / 2, course.bottom - 2, side, side),
  ];
  final area = Offset.zero & bounds;
  for (final candidate in candidates) {
    if (candidate.left < area.left ||
        candidate.right > area.right ||
        candidate.top < area.top ||
        candidate.bottom > area.bottom) {
      continue;
    }
    if (occupied.every((r) => r == course || !candidate.overlaps(r))) {
      return candidate;
    }
  }
  return Rect.fromLTWH(
    (course.center.dx - side / 2).clamp(
      0.0,
      (bounds.width - side).clamp(0.0, double.infinity),
    ),
    (course.top - side + 2).clamp(
      0.0,
      (bounds.height - side).clamp(0.0, double.infinity),
    ),
    side,
    side,
  );
}

class NaiNavigation extends StatelessWidget {
  const NaiNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.meike.paper,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Semantics(
                  selected: selected == i,
                  child: InkWell(
                    onTap: () => onSelect(i),
                    borderRadius: BorderRadius.circular(18),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: selected == i ? 1.08 : .88,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: selected == i
                                  ? context.meike.goldSoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: NaiCharacter(NaiAnimal.values[i], size: 41),
                          ),
                        ),
                        Text(
                          const ['课表', '今天', '讨论', '校园', '我的'][i],
                          style: TextStyle(
                            fontSize: 11,
                            color: selected == i
                                ? context.meike.green
                                : context.meike.muted,
                            fontWeight: selected == i
                                ? FontWeight.w600
                                : FontWeight.w400,
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
  );
}
