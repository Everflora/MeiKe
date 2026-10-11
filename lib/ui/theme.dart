import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/schedule.dart';
import 'appearance.dart';
import 'brand_wordmark.dart';

const accent = Color(0xFF24543C);
const canvas = Color(0xFFF7F7F0);
const gingko = Color(0xFFD8BC60);
const heroGreen = Color(0xFF204E38);

/// The proposed Meike palette, not a claim about the university's official VI.
@immutable
class MeikeColors extends ThemeExtension<MeikeColors> {
  const MeikeColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.green,
    required this.soft,
    required this.goldSoft,
    required this.goldInk,
    this.design = MeikeTheme.plum,
    this.hero = heroGreen,
    this.heroEnd = const Color(0xFF173E2B),
    this.onHero = const Color(0xFFFCFCED),
    this.heroAccent = gingko,
  });
  final Color paper, surface, ink, muted, line, green, soft, goldSoft, goldInk;
  final MeikeTheme design;
  final Color hero, heroEnd, onHero, heroAccent;
  static const light = MeikeColors(
    paper: canvas,
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF24382E),
    muted: Color(0xFF687369),
    line: Color(0xFFE2E6DC),
    green: accent,
    soft: Color(0xFFECF0E4),
    goldSoft: Color(0xFFF2E8BD),
    goldInk: Color(0xFF685418),
  );
  static const dark = MeikeColors(
    paper: Color(0xFF111D17),
    surface: Color(0xFF1B2B22),
    ink: Color(0xFFEDF2E8),
    muted: Color(0xFFABB8AA),
    line: Color(0xFF314438),
    green: Color(0xFFB9D49E),
    soft: Color(0xFF283C2C),
    goldSoft: Color(0xFF4A4127),
    goldInk: Color(0xFFEDDBA2),
  );
  static const ginkgoLight = MeikeColors(
    design: MeikeTheme.ginkgo,
    paper: Color(0xFFECEFE5),
    surface: Colors.white,
    ink: Color(0xFF24382E),
    muted: Color(0xFF687369),
    line: Color(0xFFE2E6DC),
    green: accent,
    soft: Color(0xFFECF0E4),
    goldSoft: Color(0xFFF2E8BD),
    goldInk: Color(0xFF685418),
  );
  static const ginkgoDark = MeikeColors(
    design: MeikeTheme.ginkgo,
    paper: Color(0xFF142119),
    surface: Color(0xFF1B2B22),
    ink: Color(0xFFEDF2E8),
    muted: Color(0xFFABB8AA),
    line: Color(0xFF314438),
    green: Color(0xFFB9D49E),
    soft: Color(0xFF283C2C),
    goldSoft: Color(0xFF4A4127),
    goldInk: Color(0xFFEDDBA2),
  );
  @override
  MeikeColors copyWith({
    Color? paper,
    Color? surface,
    Color? ink,
    Color? muted,
    Color? line,
    Color? green,
    Color? soft,
    Color? goldSoft,
    Color? goldInk,
    MeikeTheme? design,
    Color? hero,
    Color? heroEnd,
    Color? onHero,
    Color? heroAccent,
  }) => MeikeColors(
    paper: paper ?? this.paper,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    green: green ?? this.green,
    soft: soft ?? this.soft,
    goldSoft: goldSoft ?? this.goldSoft,
    goldInk: goldInk ?? this.goldInk,
    design: design ?? this.design,
    hero: hero ?? this.hero,
    heroEnd: heroEnd ?? this.heroEnd,
    onHero: onHero ?? this.onHero,
    heroAccent: heroAccent ?? this.heroAccent,
  );
  @override
  MeikeColors lerp(covariant MeikeColors? other, double t) {
    if (other == null) return this;
    return MeikeColors(
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      green: Color.lerp(green, other.green, t)!,
      soft: Color.lerp(soft, other.soft, t)!,
      goldSoft: Color.lerp(goldSoft, other.goldSoft, t)!,
      goldInk: Color.lerp(goldInk, other.goldInk, t)!,
      design: t < .5 ? design : other.design,
      hero: Color.lerp(hero, other.hero, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      heroAccent: Color.lerp(heroAccent, other.heroAccent, t)!,
    );
  }
}

extension MeikeContext on BuildContext {
  MeikeColors get meike =>
      Theme.of(this).extension<MeikeColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? MeikeColors.dark
          : MeikeColors.light);
}

ThemeData meikeTheme(
  Brightness brightness, [
  MeikeTheme design = MeikeTheme.plum,
]) {
  final dark = brightness == Brightness.dark;
  final p = design == MeikeTheme.ginkgo
      ? (dark ? MeikeColors.ginkgoDark : MeikeColors.ginkgoLight)
      : (dark ? MeikeColors.dark : MeikeColors.light);
  final scheme =
      ColorScheme.fromSeed(seedColor: p.green, brightness: brightness).copyWith(
        primary: p.green,
        onPrimary: dark ? p.paper : Colors.white,
        primaryContainer: p.soft,
        onPrimaryContainer: p.ink,
        secondary: p.goldInk,
        secondaryContainer: p.goldSoft,
        onSecondaryContainer: p.goldInk,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.muted,
        surfaceContainerHighest: p.soft,
        surfaceContainerHigh: p.soft,
        surfaceContainerLow: p.paper,
        outline: p.line,
        outlineVariant: p.line,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme
      .apply(bodyColor: p.ink, displayColor: p.ink)
      .copyWith(
        headlineLarge: TextStyle(
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        headlineMedium: TextStyle(
          fontSize: 27,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        headlineSmall: TextStyle(
          fontSize: 24,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: p.ink,
        ),
        titleSmall: TextStyle(
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w600,
          color: p.muted,
        ),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: p.ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.5, color: p.muted),
        labelSmall: TextStyle(fontSize: 11, height: 1.4, color: p.muted),
      );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  final inputShape = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );
  return base.copyWith(
    extensions: [p],
    textTheme: text,
    scaffoldBackgroundColor: p.paper,
    dividerColor: p.line,
    iconTheme: IconThemeData(color: p.green, size: 21),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(8),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: buttonShape,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        minimumSize: const Size(44, 44),
        side: BorderSide(color: p.line),
        backgroundColor: p.surface,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: buttonShape,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      border: inputShape,
      enabledBorder: inputShape,
      focusedBorder: inputShape.copyWith(
        borderSide: BorderSide(color: p.green, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      floatingLabelStyle: TextStyle(color: p.green),
      hintStyle: TextStyle(color: p.muted, fontSize: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 60,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected) ? p.green : p.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? p.green : p.muted,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: p.surface,
      selectedColor: p.soft,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(color: p.ink, fontSize: 12),
      showCheckmark: false,
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: .6, space: 20),
    listTileTheme: ListTileThemeData(
      iconColor: p.green,
      titleTextStyle: text.bodyMedium,
      subtitleTextStyle: text.bodySmall,
      minVerticalPadding: 10,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class PlumMark extends StatelessWidget {
  const PlumMark({super.key, this.size = 22, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _PlumPainter(color ?? context.meike.green),
    ),
  );
}

class _PlumPainter extends CustomPainter {
  const _PlumPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(size.width / 24);
    // Same Lucide Flower contour and stamens used by the design preview.
    final petals = Path()..moveTo(12, 16.5);
    for (final end in const [
      Offset(7.5, 12),
      Offset(12, 7.5),
      Offset(16.5, 12),
      Offset(12, 16.5),
    ]) {
      petals.arcToPoint(
        end,
        radius: const Radius.circular(4.5),
        largeArc: true,
      );
    }
    canvas.drawPath(petals, paint);
    canvas.drawCircle(const Offset(12, 12), 3, paint);
    final stamens = Path()
      ..moveTo(12, 7.5)
      ..lineTo(12, 9)
      ..moveTo(7.5, 12)
      ..lineTo(9, 12)
      ..moveTo(16.5, 12)
      ..lineTo(15, 12)
      ..moveTo(12, 16.5)
      ..lineTo(12, 15)
      ..moveTo(8, 8)
      ..lineTo(9.88, 9.88)
      ..moveTo(14.12, 9.88)
      ..lineTo(16, 8)
      ..moveTo(8, 16)
      ..lineTo(9.88, 14.12)
      ..moveTo(14.12, 14.12)
      ..lineTo(16, 16);
    canvas.drawPath(stamens, paint);
  }

  @override
  bool shouldRepaint(covariant _PlumPainter old) => old.color != color;
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 15, 20, 16),
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (context.meike.design != MeikeTheme.ginkgo) ...[
          Row(
            children: [
              const PlumMark(size: 20),
              const SizedBox(width: 7),
              MeikeWordmark(color: context.meike.green),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 15),
        ] else if (trailing != null)
          Align(alignment: Alignment.centerRight, child: trailing),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

extension CoursePalette on CourseColor {
  Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(context.meike.surface, tint, .24)!
      : pastel;
  Color foreground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Color.lerp(tint, const Color(0xFFF0F2E8), .7)!
      : Color.lerp(tint, const Color(0xFF1C3024), .18)!;
  Color get tint => const [
    Color(0xFF1F6E59),
    Color(0xFF295CA1),
    Color(0xFF965021),
    Color(0xFF6E4D9C),
    Color(0xFF9C4563),
    Color(0xFF2B7A5C),
    Color(0xFF0F666E),
    Color(0xFF176E96),
    Color(0xFF4A4FA8),
    Color(0xFF6B5CA3),
    Color(0xFF85388A),
    Color(0xFFA84A40),
    Color(0xFFA83338),
    Color(0xFF94611A),
    Color(0xFF786E0F),
    Color(0xFF57751A),
    Color(0xFF5C663B),
    Color(0xFF4D637D),
    Color(0xFF6E4F40),
    Color(0xFF7A664A),
  ][index];
  Color get pastel => const [
    Color(0xFFDBEADD),
    Color(0xFFE1E8EF),
    Color(0xFFF0E5CE),
    Color(0xFFE9E3EE),
    Color(0xFFF1E2E7),
    Color(0xFFE5EDD9),
    Color(0xFFDFEAEB),
    Color(0xFFE0EBEE),
    Color(0xFFE3E4EF),
    Color(0xFFE8E5F0),
    Color(0xFFEDE4EA),
    Color(0xFFF0E1DA),
    Color(0xFFF1DEDD),
    Color(0xFFF4EBCB),
    Color(0xFFF1EDCF),
    Color(0xFFE9EDDA),
    Color(0xFFE6E9D7),
    Color(0xFFE2E8EC),
    Color(0xFFE9DFD5),
    Color(0xFFF0E9DA),
  ][index];
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.footer,
  });
  final String title;
  final List<Widget> children;
  final String? footer;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: context.meike.green),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(footer!, style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = '确定',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: Colors.red)
                : null,
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<void> showError(BuildContext context, Object error) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('请检查'),
    content: Text(error is FormatException ? error.message : '$error'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
    ],
  ),
);

class EmptySchedule extends StatelessWidget {
  const EmptySchedule({super.key, required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.meike.soft,
            borderRadius: BorderRadius.circular(24),
          ),
          child: const PlumMark(size: 46),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

/// Outline newspaper mark matching the campus icon in the design reference.
class CampusIcon extends StatelessWidget {
  const CampusIcon({super.key});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(22),
    painter: _CampusPainter(IconTheme.of(context).color ?? context.meike.green),
  );
}

class _CampusPainter extends CustomPainter {
  const _CampusPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 2, 15, 20),
        const Radius.circular(2),
      ),
      pen,
    );
    canvas.drawPath(
      Path()
        ..moveTo(6, 6)
        ..lineTo(3, 6)
        ..lineTo(3, 19)
        ..quadraticBezierTo(3, 22, 6, 22),
      pen,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 6, 7, 5),
        const Radius.circular(1),
      ),
      pen,
    );
    canvas.drawLine(const Offset(10, 15), const Offset(17, 15), pen);
    canvas.drawLine(const Offset(10, 18), const Offset(16, 18), pen);
  }

  @override
  bool shouldRepaint(covariant _CampusPainter old) => old.color != color;
}
