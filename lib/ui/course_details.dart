import 'package:flutter/material.dart';
import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'course_editor.dart';
import 'theme.dart';

Future<void> showCourseDetails(
  BuildContext context,
  ScheduleStore store,
  Occurrence event,
) async {
  final edit = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: event.color.surface(ctx),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  color: event.color.foreground(ctx),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.makeupFor != null
                          ? '校历补课'
                          : event.isExtra
                          ? '额外安排'
                          : '常规课程',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(event.name, style: Theme.of(ctx).textTheme.titleLarge),
                  ],
                ),
              ),
              IconButton(
                tooltip: '关闭课程详情',
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _DetailRow(
            Icons.place_outlined,
            '上课地点',
            event.location.isEmpty ? '地点待定' : event.location,
          ),
          _DetailRow(
            Icons.schedule_outlined,
            '上课时间',
            '${SchoolClock.weekdays[event.weekday - 1]} · ${event.timeLabel}',
          ),
          _DetailRow(
            Icons.calendar_today_outlined,
            '本次安排',
            '${SchoolClock.fullDate(SchoolClock.date(event.week, event.weekday, store.data.semester))} · ${event.periodLabel}',
          ),
          if (event.teacher.isNotEmpty)
            _DetailRow(Icons.person_outline, '任课教师', event.teacher),
          if (event.calendarNote.isNotEmpty)
            _DetailRow(Icons.event_note, '校历调整', event.calendarNote),
          if (event.notes.isNotEmpty)
            _DetailRow(Icons.notes_outlined, '课程备注', event.notes),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: store.canWrite && !store.busy
                ? () => Navigator.pop(ctx, true)
                : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('编辑课程与上课安排'),
          ),
        ],
      ),
    ),
  );
  if (edit == true && context.mounted) {
    final course = store.data.courses
        .where((c) => c.id == event.courseId)
        .firstOrNull;
    if (course != null) await editCourse(context, store, course);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.meike.muted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 3),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    ),
  );
}
