import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'course_editor.dart';
import 'course_details.dart';
import 'courses_page.dart';
import 'school_import_page.dart';
import 'theme.dart';
import 'appearance.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage>
    with WidgetsBindingObserver {
  DateTime now = DateTime.now();
  late int selectedWeek = currentWeek;
  late String semesterKey = jsonEncode(widget.store.data.semester.toJson());
  Timer? timer;
  int get currentWeek => SchoolClock.week(
    now,
    widget.store.data.semester,
  ).clamp(1, widget.store.data.semester.weekCount);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  void refresh() {
    if (!mounted) return;
    final wasCurrent = selectedWeek == currentWeek;
    setState(() {
      now = DateTime.now();
      if (wasCurrent) selectedWeek = currentWeek;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void didUpdateWidget(covariant TimetablePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = jsonEncode(widget.store.data.semester.toJson());
    if (key != semesterKey) {
      semesterKey = key;
      selectedWeek = currentWeek;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void open(Occurrence event) =>
      showCourseDetails(context, widget.store, event);
  @override
  Widget build(BuildContext context) {
    final data = widget.store.data;
    final events = data.occurrences(selectedWeek);
    final start = SchoolClock.date(selectedWeek, 1, data.semester);
    final end = SchoolClock.date(selectedWeek, 7, data.semester);
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  tooltip: '上一周',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: selectedWeek > 1
                      ? () => setState(() => selectedWeek--)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: PopupMenuButton<int>(
                    tooltip: '选择教学周',
                    initialValue: selectedWeek,
                    onSelected: (week) => setState(() => selectedWeek = week),
                    itemBuilder: (_) => [
                      for (
                        var week = 1;
                        week <= data.semester.weekCount;
                        week++
                      )
                        PopupMenuItem(value: week, child: Text('第 $week 周')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '第 $selectedWeek 周',
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Icon(Icons.keyboard_arrow_down, size: 16),
                              ],
                            ),
                          ),
                          Text(
                            '${SchoolClock.shortDate(start)}–${SchoolClock.shortDate(end)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一周',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: selectedWeek < data.semester.weekCount
                      ? () => setState(() => selectedWeek++)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: '课程管理',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => showCourses(context, widget.store),
                  icon: const Icon(Icons.edit_note_outlined),
                ),
                IconButton(
                  tooltip: '一键导入学校课表',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 44,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.store.canWrite && !widget.store.busy
                      ? () => importSchoolSchedule(context, widget.store)
                      : null,
                  icon: const Icon(Icons.download_outlined),
                ),
                IconButton.filled(
                  tooltip: '添加课程',
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: widget.store.canWrite && !widget.store.busy
                      ? () => editCourse(context, widget.store)
                      : null,
                  icon: Icon(
                    Icons.add,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (data.courses.isEmpty)
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const EmptySchedule(
                      title: '把一周，安排得刚刚好',
                      subtitle: '添加第一门课程，开始你的新学期。',
                    ),
                    FilledButton.icon(
                      onPressed: widget.store.canWrite && !widget.store.busy
                          ? () => importSchoolSchedule(context, widget.store)
                          : null,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('一键导入学校课表'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => editCourse(context, widget.store),
                      icon: const Icon(Icons.add),
                      label: const Text('添加第一门课'),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          final candidate = data.copy()
                            ..courses = ScheduleData.demo(data.semester);
                          await widget.store.replace(candidate);
                        } catch (e) {
                          if (context.mounted) await showError(context, e);
                        }
                      },
                      child: const Text('载入示例课程'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const timeWidth = 38.0;
                final width = math.max(
                  1.0,
                  (constraints.maxWidth - timeWidth) / 7,
                );
                final allDay = events.where((e) => e.allDay).toList();
                final maxCount = [
                  for (var day = 1; day <= 7; day++)
                    allDay.where((e) => e.weekday == day).length,
                ].reduce(math.max);
                final allDayHeight = maxCount == 0
                    ? 0.0
                    : math.min(2, maxCount) * 44.0 + 4;
                final base = TimelineLayout(
                  data.semester.periods,
                  occurrences: events,
                );
                final height = math.max(
                  base.height / 2,
                  constraints.maxHeight - 44 - allDayHeight - 4,
                );
                final layout = TimelineLayout(
                  data.semester.periods,
                  occurrences: events,
                  fittingHeight: height,
                );
                return MediaQuery.withNoTextScaling(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 44,
                          child: Row(
                            children: [
                              SizedBox(
                                width: timeWidth,
                                child: Center(
                                  child: Text(
                                    '节次',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: context.meike.muted,
                                    ),
                                  ),
                                ),
                              ),
                              for (var day = 1; day <= 7; day++)
                                SizedBox(
                                  width: width,
                                  child: _DayHeader(
                                    day: day,
                                    date: SchoolClock.date(
                                      selectedWeek,
                                      day,
                                      data.semester,
                                    ),
                                    now: now,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (allDay.isNotEmpty)
                          SizedBox(
                            height: allDayHeight,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(
                                  width: timeWidth,
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Center(
                                      child: Text(
                                        '全天',
                                        style: TextStyle(fontSize: 9),
                                      ),
                                    ),
                                  ),
                                ),
                                for (var day = 1; day <= 7; day++)
                                  SizedBox(
                                    width: width,
                                    child: SingleChildScrollView(
                                      child: Column(
                                        children: [
                                          for (final e in allDay.where(
                                            (e) => e.weekday == day,
                                          ))
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    1,
                                                    0,
                                                    1,
                                                    3,
                                                  ),
                                              child: _EventCard(
                                                event: e,
                                                height: 41,
                                                onTap: () => open(e),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: timeWidth,
                              child: Column(
                                children: [
                                  for (final s in layout.segments)
                                    SizedBox(
                                      height: s.height,
                                      child: Center(
                                        child: s.period != null
                                            ? Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '${s.period}',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      height: 1.1,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  Text(
                                                    LessonPeriod.format(
                                                      s.start,
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      height: 1.2,
                                                      color:
                                                          context.meike.muted,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                s.end - s.start >= 30
                                                    ? (s.label == '午休'
                                                          ? '午休'
                                                          : '晚休')
                                                    : '${s.end - s.start}′',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: context.meike.muted,
                                                ),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            for (var day = 1; day <= 7; day++)
                              SizedBox(
                                width: width,
                                height: layout.height,
                                child: Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Column(
                                      children: [
                                        for (final s in layout.segments)
                                          Container(
                                            height: s.height,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  SchoolClock.day(
                                                        SchoolClock.date(
                                                          selectedWeek,
                                                          day,
                                                          data.semester,
                                                        ),
                                                      ) ==
                                                      SchoolClock.day(now)
                                                  ? context.meike.soft
                                                        .withValues(alpha: .45)
                                                  : context.meike.paper,
                                              border: Border(
                                                bottom: BorderSide(
                                                  color: context.meike.line
                                                      .withValues(alpha: .5),
                                                  width: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    for (final lane in OccurrenceLane.arrange(
                                      events
                                          .where(
                                            (e) =>
                                                e.weekday == day && !e.allDay,
                                          )
                                          .toList(),
                                    ))
                                      Positioned(
                                        left:
                                            1 +
                                            lane.index *
                                                (width - 2) /
                                                lane.count,
                                        top:
                                            layout.position(
                                              lane.occurrence.startMinute,
                                            ) +
                                            1,
                                        width: math.max(
                                          1,
                                          (width - 2) / lane.count - 1,
                                        ),
                                        child: _EventCard(
                                          event: lane.occurrence,
                                          height: math.max(
                                            2,
                                            layout.position(
                                                  lane.occurrence.endMinute,
                                                ) -
                                                layout.position(
                                                  lane.occurrence.startMinute,
                                                ) -
                                                2,
                                          ),
                                          layout: layout,
                                          active:
                                              SchoolClock.day(
                                                    SchoolClock.date(
                                                      selectedWeek,
                                                      day,
                                                      data.semester,
                                                    ),
                                                  ) ==
                                                  SchoolClock.day(now) &&
                                              lane.occurrence.busyRanges.any(
                                                (r) => r.contains(
                                                  SchoolClock.minute(now),
                                                ),
                                              ),
                                          onTap: () => open(lane.occurrence),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.date, required this.now});
  final int day;
  final DateTime date, now;
  @override
  Widget build(BuildContext context) {
    final today = SchoolClock.day(date) == SchoolClock.day(now);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          SchoolClock.weekdays[day - 1],
          style: TextStyle(fontSize: 10, color: context.meike.muted),
        ),
        const SizedBox(height: 2),
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: today ? gingko : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${SchoolClock.wall(date).day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: today ? const Color(0xFF24382E) : context.meike.ink,
            ),
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.height,
    required this.onTap,
    this.layout,
    this.active = false,
  });
  final Occurrence event;
  final double height;
  final VoidCallback onTap;
  final TimelineLayout? layout;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final locationHeight = event.location.isEmpty ? 0 : (height > 70 ? 20 : 11);
    final extraHeight = event.isExtra && !event.allDay && height > 70 ? 10 : 0;
    final lines = ((height - 8 - locationHeight - extraHeight) / 11)
        .floor()
        .clamp(1, 3);
    final foreground = active
        ? context.meike.onHero
        : context.meike.design == MeikeTheme.ginkgo
        ? context.meike.ink
        : event.color.foreground(context);
    return Semantics(
      label:
          '${event.name}，${SchoolClock.weekdays[event.weekday - 1]}，${event.timeLabel}，${event.location}',
      button: true,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Material(
          color: active
              ? context.meike.hero
              : context.meike.design == MeikeTheme.ginkgo
              ? context.meike.surface
              : event.color.surface(context),
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                if (context.meike.design == MeikeTheme.ginkgo)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: event.color.foreground(context),
                    ),
                  ),
                if (active)
                  Positioned(
                    top: 0,
                    right: 5,
                    child: Container(
                      width: 4,
                      height: 10,
                      decoration: BoxDecoration(
                        color: context.meike.heroAccent,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (extraHeight > 0)
                        Text(
                          '额外安排',
                          style: TextStyle(
                            fontSize: 8,
                            height: 1.1,
                            color: foreground,
                          ),
                        ),
                      Text(
                        event.name,
                        maxLines: lines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          color: foreground,
                        ),
                      ),
                      const Spacer(),
                      if (event.location.isNotEmpty)
                        if (height <= 70)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                event.location,
                                style: TextStyle(
                                  fontSize: 9,
                                  height: 1.1,
                                  color: foreground,
                                ),
                              ),
                            ),
                          )
                        else
                          Text(
                            event.location,
                            maxLines: height > 70 ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.1,
                              color: foreground,
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
