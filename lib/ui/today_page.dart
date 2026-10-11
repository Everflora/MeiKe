import 'dart:async';

import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'course_details.dart';
import 'classroom_label.dart';
import 'theme.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.store, this.clock});
  final ScheduleStore store;
  final DateTime Function()? clock;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  Timer? timer;
  late DateTime now = widget.clock?.call() ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = widget.clock?.call() ?? DateTime.now());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.store.data;
    final week = SchoolClock.week(now, data.semester);
    final courses = data.occurrences(week, weekday: SchoolClock.weekday(now));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        BrandHeader(
          title: '今天',
          subtitle: SchoolClock.fullDate(now),
          padding: const EdgeInsets.only(bottom: 24),
        ),
        _hero(context, data, courses, week),
        const SizedBox(height: 24),
        Row(
          children: [
            Text('今日安排', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: context.meike.soft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${courses.length} 项',
                style: TextStyle(fontSize: 12, color: context.meike.green),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (courses.isEmpty)
          const EmptySchedule(
            title: '今天，留一点时间给自己',
            subtitle: '没有课程安排，享受属于你的节奏。',
          ),
        for (final e in courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => showCourseDetails(context, widget.store, e),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5,
                        height: 66,
                        decoration: BoxDecoration(
                          color: e.color.foreground(context),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 7),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.place_outlined,
                                  size: 15,
                                  color: context.meike.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: ClassroomLabel(
                                    e.location.isEmpty ? '地点待定' : e.location,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${e.timeLabel} · ${e.status(now)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (e.teacher.isNotEmpty)
                              Text(
                                e.teacher,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (e.notes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(e.notes),
                              ),
                            if (courses.any(e.overlaps))
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  '与其他安排时间重叠',
                                  style: TextStyle(color: Colors.deepOrange),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        e.periodLabel,
                        style: TextStyle(
                          color: e.color.foreground(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _hero(
    BuildContext context,
    ScheduleData data,
    List<Occurrence> courses,
    int week,
  ) {
    final minute = SchoolClock.minute(now);
    final active = courses
        .where((e) => !e.allDay && e.busyRanges.any((r) => r.contains(minute)))
        .firstOrNull;
    final next =
        active ??
        courses.where((e) => !e.allDay && e.endMinute > minute).firstOrNull;
    final gap = data.breaks.where((r) => r.contains(minute)).firstOrNull;
    final semesterActive = week >= 1 && week <= data.semester.weekCount;
    final resting =
        semesterActive &&
        gap != null &&
        next != null &&
        courses.any((e) => !e.isExtra) &&
        active == null;
    final allDay = courses.where((e) => e.allDay).firstOrNull;
    final seconds = next?.secondsUntilLessonEnds(now);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [context.meike.hero, context.meike.heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: PlumMark(
              size: 140,
              color: context.meike.onHero.withValues(alpha: .08),
            ),
          ),
          DefaultTextStyle(
            style: TextStyle(color: context.meike.onHero, fontSize: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: context.meike.heroAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      resting
                          ? '休息一下'
                          : (active != null
                                ? '正在上课'
                                : next != null
                                ? '下一堂课'
                                : '按自己的节奏'),
                    ),
                    const Spacer(),
                    if (semesterActive) Text('第 $week 周'),
                  ],
                ),
                const SizedBox(height: 18),
                if (resting) ...[
                  Text(
                    gap.title,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('还可休息 ${gap.end - minute} 分钟'),
                  const SizedBox(height: 12),
                  Text('接下来 · ${next.name}'),
                  ClassroomLabel(
                    '⌖ ${next.location.isEmpty ? '地点待定' : next.location}',
                    maxLines: 1,
                  ),
                ] else if (next != null) ...[
                  Text(
                    next.name,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('◷ ${next.timeLabel}'),
                  const SizedBox(height: 6),
                  ClassroomLabel(
                    '⌖ ${next.location.isEmpty ? '地点待定' : next.location}',
                    maxLines: 1,
                  ),
                  if (seconds != null) ...[
                    const SizedBox(height: 18),
                    Text(next.isExtra ? '距离本次安排结束' : '距离本节下课'),
                    FittedBox(
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${seconds ~/ 60} 分 ${(seconds % 60).toString().padLeft(2, '0')} 秒',
                        style: TextStyle(
                          fontSize: 38,
                          color: context.meike.heroAccent,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                  if (minute < next.startMinute)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('距离开始还有 ${next.startMinute - minute} 分钟'),
                    ),
                ] else if (allDay != null) ...[
                  Text(
                    allDay.name,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClassroomLabel(
                    '全天 · ${allDay.location.isEmpty ? '地点待定' : allDay.location}',
                    maxLines: 1,
                  ),
                ] else ...[
                  Text(
                    week < 1
                        ? '新学期，等你开启'
                        : week > data.semester.weekCount
                        ? '这一学期，辛苦啦'
                        : courses.isEmpty
                        ? '今天没有课程'
                        : '今日课程已完成',
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('学习之外，也别忘了好好生活。'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
