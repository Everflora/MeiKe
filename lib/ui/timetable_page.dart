import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import '../domain/academic_calendar.dart';
import 'course_editor.dart';
import 'classroom_label.dart';
import 'course_details.dart';
import 'courses_page.dart';
import 'school_import_page.dart';
import 'theme.dart';
import 'appearance.dart';
import 'nai_family.dart';

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.store, this.clock});
  final ScheduleStore store;
  final DateTime Function()? clock;
  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage>
    with WidgetsBindingObserver {
  late DateTime now = widget.clock?.call() ?? DateTime.now();
  late int selectedWeek = currentWeek;
  late String semesterKey = jsonEncode(widget.store.data.semester.toJson());
  Timer? timer;
  double dragDistance = 0;
  int slideDirection = 1;
  int get currentWeek =>
      SchoolClock.week(now, widget.store.data.semester).clamp(
        widget.store.data.firstDisplayWeek,
        widget.store.data.lastDisplayWeek,
      );
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
      now = widget.clock?.call() ?? DateTime.now();
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

  void selectWeek(int target) {
    final data = widget.store.data;
    final week = target.clamp(data.firstDisplayWeek, data.lastDisplayWeek);
    if (week == selectedWeek) return;
    setState(() {
      slideDirection = week > selectedWeek ? 1 : -1;
      selectedWeek = week;
    });
  }

  void open(Occurrence event) =>
      showCourseDetails(context, widget.store, event);
  @override
  Widget build(BuildContext context) {
    final data = widget.store.data;
    final events = data.occurrences(selectedWeek);
    final start = SchoolClock.date(selectedWeek, 1, data.semester);
    final end = SchoolClock.date(selectedWeek, 7, data.semester);
    final ginkgo = context.meike.design == MeikeTheme.ginkgo;
    final content = <Widget>[
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
              const timeWidth = 43.0;
              final headerHeight = data.calendarTerm == null ? 44.0 : 56.0;
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
                compact: ginkgo,
                collapseBreaks: true,
              );
              final height = math.max(
                ginkgo ? base.height * 30 / 52 : base.height / 2,
                constraints.maxHeight - headerHeight - allDayHeight - 4,
              );
              final layout = TimelineLayout(
                data.semester.periods,
                occurrences: events,
                fittingHeight: height,
                compact: ginkgo,
                collapseBreaks: true,
              );
              double eventHeight(Occurrence event) =>
                  layout.position(event.endMinute) -
                  layout.position(event.startMinute);
              double eventInset(Occurrence event) =>
                  eventHeight(event) >= 4 ? 1 : 0;
              return MediaQuery.withNoTextScaling(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      SizedBox(
                        height: headerHeight,
                        child: Row(
                          children: [
                            SizedBox(
                              width: timeWidth,
                              child: Center(
                                child: Text(
                                  (ginkgo || context.naiFamily)
                                      ? '${SchoolClock.wall(start).month}月'
                                      : '节次',
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
                                  event: data.calendarEventOn(
                                    SchoolClock.date(
                                      selectedWeek,
                                      day,
                                      data.semester,
                                    ),
                                  ),
                                  events: data.calendarEventsOn(
                                    SchoolClock.date(
                                      selectedWeek,
                                      day,
                                      data.semester,
                                    ),
                                  ),
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
                                            padding: const EdgeInsets.fromLTRB(
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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: timeWidth,
                                child: Column(
                                  children: [
                                    for (final s in layout.segments.where(
                                      (s) => s.height > 0,
                                    ))
                                      SizedBox(
                                        key: ValueKey(
                                          'timetable-period-${s.period ?? s.start}',
                                        ),
                                        height: s.height,
                                        child: Center(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  s.period?.toString() ?? '额外',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    height: 1.1,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  LessonPeriod.format(
                                                    s.start,
                                                  ).replaceFirst(
                                                    RegExp(r'^0'),
                                                    '',
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    height: 1.1,
                                                    color: context.meike.muted,
                                                  ),
                                                ),
                                                Text(
                                                  '-',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    height: .8,
                                                    color: context.meike.muted,
                                                  ),
                                                ),
                                                Text(
                                                  LessonPeriod.format(
                                                    s.end,
                                                  ).replaceFirst(
                                                    RegExp(r'^0'),
                                                    '',
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    height: 1.1,
                                                    color: context.meike.muted,
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
                              for (var day = 1; day <= 7; day++)
                                SizedBox(
                                  width: width,
                                  height: layout.height,
                                  child: Stack(
                                    clipBehavior: Clip.hardEdge,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          ginkgo ? 9 : 0,
                                        ),
                                        child: Column(
                                          children: [
                                            for (final s
                                                in layout.segments.where(
                                                  (s) => s.height > 0,
                                                ))
                                              Container(
                                                height: s.height,
                                                margin:
                                                    const EdgeInsets.symmetric(
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
                                                            .withValues(
                                                              alpha: .45,
                                                            )
                                                      : ginkgo
                                                      ? context.meike.surface
                                                      : context.meike.paper,
                                                  border: Border(
                                                    bottom: BorderSide(
                                                      color: context.meike.line
                                                          .withValues(
                                                            alpha: .5,
                                                          ),
                                                      width: 0.5,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
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
                                              eventInset(lane.occurrence),
                                          width: math.max(
                                            1,
                                            (width - 2) / lane.count - 1,
                                          ),
                                          child: _EventCard(
                                            event: lane.occurrence,
                                            height:
                                                eventHeight(lane.occurrence) -
                                                2 * eventInset(lane.occurrence),
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
                                      if (ginkgo &&
                                          SchoolClock.day(
                                                SchoolClock.date(
                                                  selectedWeek,
                                                  day,
                                                  data.semester,
                                                ),
                                              ) ==
                                              SchoolClock.day(now) &&
                                          SchoolClock.minute(now) >=
                                              layout.segments.first.start &&
                                          SchoolClock.minute(now) <
                                              layout.segments.last.end)
                                        Positioned(
                                          top: layout.position(
                                            SchoolClock.minute(now),
                                          ),
                                          left: 1,
                                          right: 1,
                                          child: IgnorePointer(
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Container(
                                                  height: 1.5,
                                                  color: gingko,
                                                ),
                                                Positioned(
                                                  left: 0,
                                                  top: -1.5,
                                                  child: Container(
                                                    width: 4,
                                                    height: 4,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: gingko,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          if (context.naiFamily)
                            ..._eggMarkers(events, layout, width, timeWidth),
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
    ];
    final page = ColoredBox(
      key: ValueKey(selectedWeek),
      color: context.meike.paper,
      child: Column(
        children: [
          if (!ginkgo)
            SizedBox(
              height: context.naiFamily ? 56 : 48,
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
                      onPressed: selectedWeek > data.firstDisplayWeek
                          ? () => selectWeek(selectedWeek - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: PopupMenuButton<int>(
                        tooltip: '选择教学周',
                        initialValue: selectedWeek,
                        onSelected: (week) => selectWeek(week),
                        itemBuilder: (_) => [
                          for (
                            var week = data.firstDisplayWeek;
                            week <= data.lastDisplayWeek;
                            week++
                          )
                            PopupMenuItem(
                              value: week,
                              child: Text(data.weekLabel(week)),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: context.naiFamily
                                ? CrossAxisAlignment.start
                                : CrossAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      data.weekLabel(selectedWeek),
                                      style: TextStyle(
                                        fontSize: context.naiFamily ? 22 : 17,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 16,
                                    ),
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
                      onPressed: selectedWeek < data.lastDisplayWeek
                          ? () => selectWeek(selectedWeek + 1)
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
                        backgroundColor: context.naiFamily
                            ? context.meike.heroAccent
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: context.naiFamily
                              ? const BorderRadius.vertical(
                                  top: Radius.circular(22),
                                  bottom: Radius.circular(16),
                                )
                              : BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.store.canWrite && !widget.store.busy
                          ? () => editCourse(context, widget.store)
                          : null,
                      icon: context.naiFamily
                          ? const NaiAddGlyph()
                          : Icon(
                              Icons.add,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          if (ginkgo)
            Expanded(
              child: Container(
                key: const ValueKey('ginkgo-calendar-panel'),
                margin: const EdgeInsets.fromLTRB(9, 10, 9, 4),
                padding: const EdgeInsets.fromLTRB(5, 4, 5, 8),
                decoration: BoxDecoration(
                  color: context.meike.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(children: [_ginkgoWeek(start, end), ...content]),
              ),
            )
          else
            ...content,
        ],
      ),
    );
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => dragDistance = 0,
        onHorizontalDragUpdate: (details) =>
            dragDistance += details.primaryDelta ?? 0,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (dragDistance.abs() < 40 && velocity.abs() < 250) return;
          final right = dragDistance.abs() >= 40
              ? dragDistance > 0
              : velocity > 0;
          selectWeek(selectedWeek + (right ? -1 : 1));
        },
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final incoming = child.key == ValueKey(selectedWeek);
            final offset = (incoming ? 1.0 : -1.0) * slideDirection;
            return SlideTransition(
              position: Tween<Offset>(
                begin: Offset(offset, 0),
                end: Offset.zero,
              ).animate(animation),
              child: IgnorePointer(
                ignoring: !incoming,
                child: ExcludeSemantics(excluding: !incoming, child: child),
              ),
            );
          },
          child: page,
        ),
      ),
    );
  }

  List<Widget> _eggMarkers(
    List<Occurrence> events,
    TimelineLayout layout,
    double width,
    double timeWidth,
  ) {
    final entries = <(Occurrence, Rect)>[];
    for (var day = 1; day <= 7; day++) {
      for (final lane in OccurrenceLane.arrange(
        events.where((e) => e.weekday == day && !e.allDay).toList(),
      )) {
        final e = lane.occurrence;
        final height =
            layout.position(e.endMinute) - layout.position(e.startMinute);
        final inset = height >= 4 ? 1.0 : 0.0;
        entries.add((
          e,
          Rect.fromLTWH(
            (day - 1) * width + 1 + lane.index * (width - 2) / lane.count,
            layout.position(e.startMinute) + inset,
            math.max(1, (width - 2) / lane.count - 1),
            height - 2 * inset,
          ),
        ));
      }
    }
    final occupied = entries.map((e) => e.$2).toList();
    final active = entries
        .where(
          (entry) =>
              SchoolClock.day(
                    SchoolClock.date(
                      selectedWeek,
                      entry.$1.weekday,
                      widget.store.data.semester,
                    ),
                  ) ==
                  SchoolClock.day(now) &&
              entry.$1.busyRanges.any(
                (r) => r.contains(SchoolClock.minute(now)),
              ),
        )
        .firstOrNull;
    if (active == null) return [];
    final rect = naiEggPlacement(
      active.$2,
      occupied,
      Size(width * 7, layout.height),
    );
    return [
      Positioned(
        left: timeWidth + rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: Semantics(
          label: '奶蛋：正在上课，${active.$1.name}，点按查看详情',
          button: true,
          child: GestureDetector(
            key: const ValueKey('nai-active-egg'),
            onTap: () => open(active.$1),
            child: const NaiCharacter(NaiAnimal.egg),
          ),
        ),
      ),
    ];
  }

  Widget _ginkgoWeek(DateTime start, DateTime end) => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          tooltip: '上一周',
          onPressed: selectedWeek > widget.store.data.firstDisplayWeek
              ? () => selectWeek(selectedWeek - 1)
              : null,
          icon: const Icon(Icons.chevron_left, size: 21),
        ),
        PopupMenuButton<int>(
          tooltip: '选择教学周',
          initialValue: selectedWeek,
          onSelected: (week) => selectWeek(week),
          itemBuilder: (_) => [
            for (
              var week = widget.store.data.firstDisplayWeek;
              week <= widget.store.data.lastDisplayWeek;
              week++
            )
              PopupMenuItem(
                value: week,
                child: Text(widget.store.data.weekLabel(week)),
              ),
          ],
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.store.data.weekLabel(selectedWeek),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.meike.ink,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down, size: 16),
            ],
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            '${SchoolClock.shortDate(start)}–${SchoolClock.shortDate(end)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.meike.muted),
          ),
        ),
        IconButton(
          tooltip: '下一周',
          onPressed: selectedWeek < widget.store.data.lastDisplayWeek
              ? () => selectWeek(selectedWeek + 1)
              : null,
          icon: const Icon(Icons.chevron_right, size: 21),
        ),
      ],
    ),
  );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.date,
    required this.now,
    this.event,
    this.events = const [],
  });
  final int day;
  final DateTime date, now;
  final CalendarEvent? event;
  final List<CalendarEvent> events;
  @override
  Widget build(BuildContext context) {
    final today = SchoolClock.day(date) == SchoolClock.day(now);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          (context.meike.design == MeikeTheme.ginkgo || context.naiFamily)
              ? '一二三四五六日'[day - 1]
              : SchoolClock.weekdays[day - 1],
          style: TextStyle(fontSize: 10, color: context.meike.muted),
        ),
        const SizedBox(height: 2),
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: today
                ? (context.naiFamily ? context.meike.green : gingko)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${SchoolClock.wall(date).day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: today
                  ? (context.naiFamily
                        ? Theme.of(context).colorScheme.onPrimary
                        : const Color(0xFF24382E))
                  : context.meike.ink,
            ),
          ),
        ),
        if (event != null)
          Tooltip(
            message: '${event!.title}：${event!.details}',
            child: InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    '${SchoolClock.shortDate(date)} · ${event!.title}',
                  ),
                  content: SingleChildScrollView(
                    child: Text(
                      events.map((e) => '${e.title}：${e.details}').join('\n\n'),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
              child: Text(
                event!.badge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  height: 1.1,
                  color: context.meike.green,
                  fontWeight: FontWeight.w600,
                ),
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
    final rows = event.isExtra || event.allDay
        ? <TimelineSegment>[]
        : (layout?.segments ?? <TimelineSegment>[])
              .where(
                (s) =>
                    s.period != null &&
                    event.busyRanges.any(
                      (r) => r.start < s.end && r.end > s.start,
                    ),
              )
              .toList();
    final segmented = rows.length > 1;
    final firstRowHeight = segmented ? rows.first.height - 2 : height;
    final lastRowHeight = segmented ? rows.last.height - 2 : height;
    final roomLines = segmented
        ? (lastRowHeight >= 36 ? 2 : 1)
        : (height > 70 ? 2 : 1);
    final locationHeight = event.location.isEmpty ? 0 : roomLines * 10;
    final extraHeight = event.isExtra && !event.allDay && height > 70 ? 10 : 0;
    final lines =
        ((firstRowHeight - 8 - (segmented ? 0 : locationHeight) - extraHeight) /
                12.1)
            .floor()
            .clamp(1, 3);
    final ginkgo = context.meike.design == MeikeTheme.ginkgo;
    final title =
        '${event.makeupFor != null
            ? '补·'
            : event.isExtra && event.calendarNote.isNotEmpty
            ? '额·'
            : ''}${event.name}';
    // Keep the true time position and height. Short events use a single title
    // line; their full location and time remain available in course details.
    final compact =
        event.isExtra &&
        !event.allDay &&
        height + .01 < 6 + 12.1 + (event.location.isEmpty ? 0 : 9.9);
    final foreground = active
        ? (context.naiFamily
              ? context.meike.ink
              : ginkgo
              ? context.meike.goldInk
              : context.meike.onHero)
        : (context.meike.design == MeikeTheme.ginkgo || context.naiFamily)
        ? context.meike.ink
        : event.color.foreground(context);
    return Semantics(
      label:
          '${event.name}，${SchoolClock.weekdays[event.weekday - 1]}，${event.periodLabel}，${event.timeLabel}，${event.location}，${event.calendarNote}',
      button: true,
      excludeSemantics: true,
      child: Container(
        height: height,
        decoration: context.naiFamily && active
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: context.meike.green.withValues(alpha: .2),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              )
            : null,
        child: Material(
          key: context.naiFamily && active
              ? const ValueKey('nai-active-course-border')
              : null,
          color: active
              ? (ginkgo || context.naiFamily
                    ? context.meike.goldSoft
                    : context.meike.hero)
              : context.meike.design == MeikeTheme.ginkgo
              ? context.meike.surface
              : context.naiFamily
              ? Color.lerp(
                  event.color.surface(context),
                  context.meike.soft,
                  .62,
                )!
              : event.color.surface(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ginkgo ? 5 : 7),
            side: context.naiFamily && active
                ? BorderSide(color: context.meike.green, width: 2)
                : ginkgo
                ? BorderSide(color: context.meike.line, width: .7)
                : BorderSide.none,
          ),
          clipBehavior: Clip.hardEdge,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                if (segmented)
                  for (final row in rows.skip(1))
                    Positioned(
                      key: ValueKey('course-divider-${event.id}-${row.period}'),
                      top: row.y - layout!.position(event.startMinute) - 1,
                      left: 2,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: .8,
                          color: foreground.withValues(alpha: .22),
                        ),
                      ),
                    ),
                if (context.meike.design == MeikeTheme.ginkgo)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 2,
                      color: active
                          ? context.meike.goldInk
                          : event.color.foreground(context),
                    ),
                  ),
                if (active && !context.naiFamily)
                  Positioned(
                    top: 0,
                    right: 5,
                    child: Container(
                      width: 4,
                      height: 10,
                      decoration: BoxDecoration(
                        color: ginkgo ? gingko : context.meike.heroAccent,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                if (compact)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: math.min(11, height / 1.1),
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            color: foreground,
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (extraHeight > 0)
                          Text(
                            event.calendarNote.isNotEmpty ? '停课日额外安排' : '额外安排',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 8,
                              height: 1.1,
                              color: foreground,
                            ),
                          ),
                        Text(
                          title,
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
                        if (segmented)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              event.periodLabel,
                              style: TextStyle(
                                fontSize: 8,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: foreground.withValues(alpha: .85),
                              ),
                            ),
                          ),
                        if (event.location.isNotEmpty)
                          ClassroomLabel(
                            event.location,
                            maxLines: roomLines,
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
