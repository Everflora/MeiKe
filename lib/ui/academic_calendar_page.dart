import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_school_page.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../data/schedule_store.dart';
import '../domain/academic_calendar.dart';
import '../domain/schedule.dart';
import 'theme.dart';

class AcademicCalendarPanel extends StatefulWidget {
  const AcademicCalendarPanel({super.key, required this.store, this.clock});
  final ScheduleStore store;
  final DateTime Function()? clock;
  @override
  State<AcademicCalendarPanel> createState() => _AcademicCalendarPanelState();
}

class _AcademicCalendarPanelState extends State<AcademicCalendarPanel> {
  late DateTime selected = _initialDay();
  late DateTime month = DateTime.utc(selected.year, selected.month);
  DateTime _initialDay() {
    final now = SchoolClock.day(widget.clock?.call() ?? DateTime.now());
    return now.isBefore(DateTime.utc(2026, 8)) ||
            now.isAfter(DateTime.utc(2027, 8, 31))
        ? DateTime.utc(2026, 9, 21)
        : now;
  }

  void move(int delta) => setState(() {
    month = DateTime.utc(month.year, month.month + delta);
    selected = month;
  });
  Future<void> apply(CalendarTerm term) async {
    final old = widget.store.data;
    final neededWeeks = [
      term.weeks,
      for (final c in old.courses) ...[
        for (final m in c.meetings) m.endWeek,
        for (final e in c.extras) e.week,
      ],
    ].reduce(math.max);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('使用${term.name}校历？'),
        content: Text(
          '第1周周一设为${SchoolClock.fullDate(term.firstMonday)}，保留 $neededWeeks 周。已有课程和额外安排的日期会随学期起点移动，课程内容不删除。停课与补课只影响显示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('使用校历'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final candidate = old.copy();
    candidate.semester.startDate = term.firstMonday.subtract(
      SchoolClock.offset,
    );
    candidate.semester.weekCount = neededWeeks;
    candidate.semester.useSchoolCalendar = true;
    if (candidate.semester.name == '我的学期') {
      candidate.semester.name = '${SeuCalendar.year} ${term.name}';
    }
    try {
      await widget.store.replace(candidate);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextMonth = DateTime.utc(month.year, month.month + 1);
    final count = nextMonth.subtract(const Duration(days: 1)).day;
    final blanks = month.weekday - 1;
    final daily = SeuCalendar.on(selected);
    final monthly = SeuCalendar.events.where(
      (e) => !e.end.isBefore(month) && e.start.isBefore(nextMonth),
    );
    final term = widget.store.data.calendarTerm;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          '东南大学 ${SeuCalendar.year} 学年校历',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text('无需登录 · 离线可看', style: TextStyle(color: context.meike.green)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '校历上个月',
                      onPressed: month.isAfter(DateTime.utc(2026, 8))
                          ? () => move(-1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${month.year}年${month.month}月',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: '校历下个月',
                      onPressed: month.isBefore(DateTime.utc(2027, 8))
                          ? () => move(1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final day in '一二三四五六日'.split(''))
                      Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: 58,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemCount: ((blanks + count + 6) ~/ 7) * 7,
                  itemBuilder: (context, index) {
                    final number = index - blanks + 1;
                    if (number < 1 || number > count) return const SizedBox();
                    final date = DateTime.utc(month.year, month.month, number);
                    final event = SeuCalendar.highlight(date);
                    final active = date == selected;
                    return Semantics(
                      label:
                          '${CalendarEvent.shortDate(date)} ${event?.title ?? ''}',
                      button: true,
                      child: Material(
                        color: active
                            ? context.meike.goldSoft
                            : event?.stopsClasses == true
                            ? context.meike.soft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => selected = date),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 5,
                              horizontal: 1,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '$number',
                                  textScaler: TextScaler.noScaling,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: active
                                        ? context.meike.goldInk
                                        : context.meike.ink,
                                  ),
                                ),
                                if (event != null)
                                  Text(
                                    event.badge,
                                    textScaler: TextScaler.noScaling,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: context.meike.green,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${CalendarEvent.shortDate(selected)} 的校历安排',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (daily.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('这一天没有特别校历安排。'),
          ),
        for (final event in daily) _eventCard(context, event),
        const SizedBox(height: 16),
        Text('课表联动', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          term == null
              ? '当前学期起点尚未匹配本校历，或已关闭联动。选择下方学期启用。'
              : '当前课表已联动${term.name}：停课日隐藏常规课程，补课日按原日期排课。',
        ),
        const Text('手动额外安排保留并标注。可在「我的 → 学期与作息」关闭联动；原始课程不删除。'),
        for (final t in SeuCalendar.terms)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t.name),
            subtitle: Text(
              '${CalendarEvent.shortDate(t.start)}–${CalendarEvent.shortDate(t.end)} · ${t.weeks}周',
            ),
            trailing: TextButton(
              onPressed: widget.store.canWrite && !widget.store.busy
                  ? () => apply(t)
                  : null,
              child: Text(term == t ? '已联动' : '设为课表学期'),
            ),
          ),
        const SizedBox(height: 12),
        Text('本月安排', style: Theme.of(context).textTheme.titleMedium),
        for (final event in monthly) _eventCard(context, event),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined),
          label: const Text('查看全年校历原图'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const CalendarImagePage()),
          ),
        ),
        TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('查看学校官网校历'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const CalendarSourcePage()),
          ),
        ),
        const Text(
          '来源：东南大学教务处2026—2027学年校历及2026年节假日通知。2027年法定假期和调休尚未收录，本版本不推测日期；具体考试与专项工作以学校后续通知为准。',
        ),
      ],
    );
  }

  Widget _eventCard(BuildContext context, CalendarEvent event) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${event.title} · ${event.dateLabel}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 5),
          Text(event.details),
        ],
      ),
    ),
  );
}

class CalendarImagePage extends StatelessWidget {
  const CalendarImagePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('全年校历原图')),
    body: Center(
      child: InteractiveViewer(
        minScale: .5,
        maxScale: 6,
        child: Image.asset('assets/seu-calendar-2026-2027.jpg'),
      ),
    ),
  );
}

class CalendarSourcePage extends StatefulWidget {
  const CalendarSourcePage({super.key});
  @override
  State<CalendarSourcePage> createState() => _CalendarSourcePageState();
}

class _CalendarSourcePageState extends State<CalendarSourcePage> {
  late final controller = WebViewController()
    ..loadRequest(Uri.parse(SeuCalendar.source));
  @override
  Widget build(BuildContext context) => kIsWeb
      ? const WebSchoolPage(title: '学校官网校历', url: SeuCalendar.source)
      : Scaffold(
          appBar: AppBar(title: const Text('学校官网校历')),
          body: WebViewWidget(controller: controller),
        );
}
