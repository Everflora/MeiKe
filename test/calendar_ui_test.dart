import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/academic_calendar_page.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/theme.dart';
import 'package:seu_timetable/ui/timetable_page.dart';
import 'package:seu_timetable/ui/today_page.dart';

void main() {
  late Directory dir;
  late ScheduleStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meike-calendar-ui-');
    store = ScheduleStore(File('${dir.path}/schedule.json'));
    await store.load();
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  void small(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('校园有离线校历入口，无需登录，可浏览月份和全年原图', (tester) async {
    small(tester);
    await tester.runAsync(() async {
      await tester.pumpWidget(SeuTimetableApp(store: store));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(NavigationDestination, '校园'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '校历'));
    await tester.pumpAndSettle();
    expect(find.text('无需登录 · 离线可看'), findsOneWidget);
    expect(find.text('东南大学 2026—2027 学年校历'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('查看全年校历原图'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(AcademicCalendarPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('查看全年校历原图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看全年校历原图'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('选择校历需确认，保留课程和超过18周的额外安排，取消不改变原课表', (tester) async {
    await tester.runAsync(
      () => store.replace(
        ScheduleData(
          semester: Semester(startDate: SchoolClock.instant(2025, 9, 22)),
          courses: [
            Course(name: '保留课程', extras: [ExtraMeeting(week: 20)]),
          ],
        ),
      ),
    );
    final before = store.data.toJson();
    await tester.pumpWidget(
      MaterialApp(
        theme: meikeTheme(Brightness.light),
        home: Scaffold(body: AcademicCalendarPanel(store: store)),
      ),
    );
    await tester.pumpAndSettle();
    final target = find.descendant(
      of: find.ancestor(of: find.text('秋季学期'), matching: find.byType(ListTile)),
      matching: find.byType(TextButton),
    );
    await tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.data.toJson(), before);
    await tester.tap(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用校历'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && store.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
    expect(store.busy, isFalse);
    expect(store.data.semester.startDate, SchoolClock.instant(2026, 9, 21));
    expect(store.data.semester.weekCount, 20);
    expect(store.data.courses.single.name, '保留课程');
    expect(store.data.courses.single.extras.single.week, 20);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('课表能选开学补课周，国庆补课标注原日期，校运会没有常规课程', (tester) async {
    small(tester);
    await tester.runAsync(
      () => store.replace(
        ScheduleData(
          semester: Semester(
            startDate: SchoolClock.instant(2026, 9, 21),
            weekCount: 16,
          ),
          courses: [
            Course(
              name: '周二课程',
              meetings: [WeeklyMeeting(weekday: 2, startWeek: 3, endWeek: 3)],
            ),
            Course(
              name: '周三课程',
              location: '教三-304',
              meetings: [WeeklyMeeting(weekday: 3, startWeek: 3, endWeek: 3)],
            ),
            Course(
              name: '周四课程',
              meetings: [WeeklyMeeting(weekday: 4, endWeek: 16)],
              extras: [
                ExtraMeeting(
                  title: '单独实验',
                  week: 7,
                  weekday: 4,
                  startMinute: 840,
                  endMinute: 935,
                  location: '实301',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    for (final design in MeikeTheme.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: meikeTheme(Brightness.light, design),
          home: Scaffold(body: TimetablePage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> week(String label) async {
        await tester.tap(find.byTooltip('选择教学周'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await week('开学补课周');
      expect(find.text('补·周二课程'), findsOneWidget);
      expect(find.text('补课'), findsOneWidget);
      await week('第 3 周');
      expect(find.text('补·周三课程'), findsOneWidget);
      expect(find.text('周四课程'), findsOneWidget); // 10.8 is a normal Thursday.
      await tester.tap(find.text('补·周三课程'));
      await tester.pumpAndSettle();
      expect(find.text('校历补课'), findsOneWidget);
      expect(find.textContaining('补10.7周三'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭课程详情'));
      await tester.pumpAndSettle();
      await week('第 7 周');
      expect(find.text('周四课程'), findsNothing);
      expect(find.text('校运会'), findsNWidgets(3));
      expect(find.text('额·周四课程 · 单独实验'), findsOneWidget);
      await tester.tap(find.text('额·周四课程 · 单独实验'));
      await tester.pumpAndSettle();
      expect(find.textContaining('校运会 · 停课日额外安排'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭课程详情'));
      await tester.pumpAndSettle();
      await week('第 18 周');
      expect(find.text('考试'), findsNWidgets(7));
      expect(store.data.semester.weekCount, 16);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('今天页在假期不误报正在上课，补课日使用调整课程和倒计时', (tester) async {
    await tester.runAsync(
      () => store.replace(
        ScheduleData(
          semester: Semester(startDate: SchoolClock.instant(2026, 9, 21)),
          courses: [
            Course(
              name: '网络课',
              location: '实验室',
              meetings: [
                WeeklyMeeting(weekday: 3, startPeriod: 3, endPeriod: 4),
              ],
            ),
          ],
        ),
      ),
    );
    Future<void> day(DateTime now) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: meikeTheme(Brightness.dark),
          home: Scaffold(
            body: TodayPage(key: ValueKey(now), store: store, clock: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await day(SchoolClock.instant(2026, 10, 7, 10));
    expect(find.text('正在上课'), findsNothing);
    expect(find.text('网络课'), findsNothing);
    expect(find.textContaining('国庆节'), findsWidgets);
    await day(SchoolClock.instant(2026, 10, 10, 10));
    expect(find.text('正在上课'), findsOneWidget);
    expect(find.text('网络课'), findsWidgets);
    expect(find.textContaining('国庆补课'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('校历月历在小屏深色大字模式不溢出', (tester) async {
    small(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: meikeTheme(Brightness.dark, MeikeTheme.ginkgo),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: AcademicCalendarPanel(
            store: store,
            clock: () => SchoolClock.instant(2026, 10, 12),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('校历下个月'));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    expect(find.text('校运会'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
