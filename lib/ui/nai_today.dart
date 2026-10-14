import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'classroom_label.dart';
import 'course_details.dart';
import 'nai_family.dart';
import 'theme.dart';

const naiTodayGold = Color(0xFFE0C055);
const naiTodayInk = Color(0xFF173B28);

class NaiTodayContent extends StatelessWidget {
  const NaiTodayContent({super.key, required this.store, required this.now});
  final ScheduleStore store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final data = store.data;
    final week = SchoolClock.week(now, data.semester);
    final courses = data.occurrences(week, weekday: SchoolClock.weekday(now));
    final minute = SchoolClock.minute(now);
    final active = courses
        .where((e) => !e.allDay && e.busyRanges.any((r) => r.contains(minute)))
        .firstOrNull;
    final next =
        active ??
        courses.where((e) => !e.allDay && e.endMinute > minute).firstOrNull;
    final allDay = courses.where((e) => e.allDay).firstOrNull;
    final empty = courses.isEmpty;
    final done = !empty && next == null && allDay == null;
    final resting =
        active == null &&
        next != null &&
        courses.any((e) => !e.allDay && e.startMinute < minute);
    final lessonCount = courses
        .where((e) => !e.isExtra)
        .fold(0, (sum, e) => sum + e.busyRanges.length);
    final extras = courses.where((e) => e.isExtra).length;
    final headline = empty
        ? '今日份放空'
        : done
        ? '今日份完成'
        : active != null
        ? '今日份开机'
        : resting
        ? '今日份缓冲'
        : '今日份准备';
    final badge = empty
        ? '今天没有课程'
        : done
        ? '今日课程已结束'
        : active != null
        ? '正在上课 · ${active.name}'
        : resting
        ? '课间休息'
        : next != null
        ? '下一堂课 · ${next.name}'
        : '今日全天安排';
    final copy = empty
        ? '今天的安排\n做一颗奶蛋'
        : done
        ? '下课了\n有事明天说'
        : active != null
        ? '人在教室\n脑子正在加载'
        : resting
        ? '短暂休息\n脑子缓冲一下'
        : next != null
        ? '上课前准备\n奶鸡先醒一步'
        : '今天的安排\n慢慢来就好';
    final animal = empty || allDay != null && next == null
        ? NaiAnimal.egg
        : done
        ? NaiAnimal.frogBack
        : active != null || resting
        ? NaiAnimal.frog
        : NaiAnimal.chicken;
    final summary = empty
        ? '课表空空 脑袋也空空\n放心休息 明天再说'
        : done
        ? (lessonCount > 0
              ? '今天$lessonCount节课全部结束\n下一站食堂'
              : '今天${courses.length}项安排全部结束\n好好休息')
        : resting
        ? '接下来 ${next.name}\n${next.location.isEmpty ? '地点待定' : next.location}'
        : next != null
        ? '${next.name}\n${next.location.isEmpty ? '地点待定' : next.location}'
        : '${allDay!.name}\n${allDay.location.isEmpty ? '地点待定' : allDay.location}';
    final seconds = active?.secondsUntilLessonEnds(now);
    final currentRange = active?.busyRanges
        .where((r) => r.contains(minute))
        .firstOrNull;
    final wall = SchoolClock.wall(now);
    final date =
        '${wall.month} 月 ${wall.day} 日 · ${SchoolClock.weekdays[wall.weekday - 1]} / ${data.weekLabel(week)}';
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF232A20)
          : context.meike.paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          Text(date, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Text(
            headline,
            key: const ValueKey('nai-today-headline'),
            style: TextStyle(
              fontSize: 29,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: context.meike.ink,
            ),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, box) {
              final small = box.maxWidth < 300;
              final scaler = MediaQuery.textScalerOf(context);
              final scale = scaler.scale(12) / 12;
              final copyStyle = TextStyle(
                fontSize: small ? 25 : 28,
                height: 1.32,
                fontWeight: FontWeight.w600,
                color: naiTodayInk,
              );
              double measure(String value, TextStyle style, double width) {
                final painter = TextPainter(
                  text: TextSpan(text: value, style: style),
                  textDirection: TextDirection.ltr,
                  textScaler: scaler,
                )..layout(maxWidth: width);
                final result = painter.height;
                painter.dispose();
                return result;
              }

              final copyTop = 76.0 + 14.0 * math.max(0.0, scale - 1);
              final footerHeight = active != null && seconds != null
                  ? 60.0 +
                        measure(
                          active.isExtra
                              ? '本次安排 ${LessonPeriod.format(active.endMinute)} 结束'
                              : '本节 ${LessonPeriod.format(currentRange!.end)} 下课\n本次连堂课 ${LessonPeriod.format(active.endMinute)} 结束',
                          const TextStyle(fontSize: 12, height: 1.55),
                          box.maxWidth * .58,
                        )
                  : measure(
                          summary,
                          const TextStyle(fontSize: 12, height: 1.55),
                          box.maxWidth * .58,
                        ) +
                        (next != null && minute < next.startMinute
                            ? 20 * scale
                            : 0);
              final cardHeight = math.max(
                active != null ? (small ? 310.0 : 320.0) : 282.0,
                copyTop +
                    measure(copy, copyStyle, box.maxWidth - 36) +
                    22 +
                    footerHeight +
                    24,
              );
              return ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: SizedBox(
                  height: cardHeight,
                  child: ColoredBox(
                    key: const ValueKey('nai-today-gold-card'),
                    color: naiTodayGold,
                    child: Stack(
                      children: [
                        Positioned(
                          right: -46,
                          bottom: -30,
                          child: Container(
                            width: box.maxWidth * .75,
                            height: cardHeight * .80,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEDD482),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Positioned(
                          right: -10,
                          bottom: done ? -16 : -8,
                          width: box.maxWidth * .56,
                          height: cardHeight * .86,
                          child: Image.asset(
                            'assets/nai-family/${animal.asset}.webp',
                            fit: BoxFit.contain,
                            alignment: Alignment.bottomRight,
                            excludeFromSemantics: true,
                          ),
                        ),
                        Positioned(
                          left: 20,
                          top: 20,
                          right: 16,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4E3A0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badge,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: naiTodayInk,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          top: copyTop,
                          right: 16,
                          child: Text(
                            copy,
                            key: const ValueKey('nai-today-copy'),
                            style: copyStyle,
                          ),
                        ),
                        Positioned(
                          left: 20,
                          bottom: 24,
                          width: box.maxWidth * .58,
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.55,
                              color: naiTodayInk,
                            ),
                            child: Column(
                              key: const ValueKey('nai-today-footer'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (active != null && seconds != null) ...[
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '${(seconds / 60).ceil()}',
                                          style: const TextStyle(
                                            fontSize: 52,
                                            height: 1.0,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          active.isExtra ? ' 分钟结束' : ' 分钟下课',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    active.isExtra
                                        ? '本次安排 ${LessonPeriod.format(active.endMinute)} 结束'
                                        : '本节 ${LessonPeriod.format(currentRange!.end)} 下课',
                                  ),
                                  if (!active.isExtra)
                                    Text(
                                      '本次连堂课 ${LessonPeriod.format(active.endMinute)} 结束',
                                    ),
                                ] else ...[
                                  Text(
                                    summary,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (next != null && minute < next.startMinute)
                                    Text(
                                      '距离开始还有 ${next.startMinute - minute} 分钟',
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          for (final event in data.calendarEventsOn(now))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${event.title} · ${event.dateLabel}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(event.details),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  empty ? '空白也很好' : '今天的课程',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Flexible(
                child: Text(
                  empty
                      ? '0 节课'
                      : '${courses.map((e) => e.courseId).toSet().length} 门课 · $lessonCount 节${extras > 0 ? ' · $extras 项额外安排' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (empty)
            Text(
              '奶蛋陪你发呆。额外添加的实验和补课仍会正常显示。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          for (final e in courses) _lesson(context, e),
        ],
      ),
    );
  }

  Widget _lesson(BuildContext context, Occurrence e) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    color: Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF30372A)
        : context.meike.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: context.meike.line, width: .7),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showCourseDetails(context, store, e),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                e.allDay
                    ? '全天'
                    : '${LessonPeriod.format(e.startMinute).replaceFirst(RegExp(r'^0'), '')}\n${LessonPeriod.format(e.endMinute).replaceFirst(RegExp(r'^0'), '')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Container(width: 3, height: 48, color: naiTodayGold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, style: Theme.of(context).textTheme.titleMedium),
                  ClassroomLabel(
                    '${e.location.isEmpty ? '地点待定' : e.location} · ${e.periodLabel} · ${e.status(now)}',
                    maxLines: 2,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (e.calendarNote.isNotEmpty)
                    Text(
                      e.calendarNote,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
