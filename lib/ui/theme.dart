import 'package:flutter/material.dart';

import '../domain/schedule.dart';

const accent = Color(0xFF1F6E59);
const canvas = Color(0xFFF3F5F2);

extension CoursePalette on CourseColor {
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
    Color(0xFFD1EBDB),
    Color(0xFFD6E8FA),
    Color(0xFFFCE3C4),
    Color(0xFFE8DBF7),
    Color(0xFFFAD9E0),
    Color(0xFFD6F5E0),
    Color(0xFFC7EBEB),
    Color(0xFFCCF0FC),
    Color(0xFFD6DBFA),
    Color(0xFFEBE6FC),
    Color(0xFFF0D4F2),
    Color(0xFFFFD9CF),
    Color(0xFFFCCECF),
    Color(0xFFFFE3AD),
    Color(0xFFFCF5B8),
    Color(0xFFE3F2BD),
    Color(0xFFDEE6C7),
    Color(0xFFDBE8F2),
    Color(0xFFE0CFC2),
    Color(0xFFF5EBCF),
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
            ).textTheme.titleSmall?.copyWith(color: accent),
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
        const Icon(Icons.menu_book_rounded, size: 54, color: accent),
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
