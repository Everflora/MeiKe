import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/nai_family.dart';
import 'package:seu_timetable/ui/theme.dart';
import 'package:seu_timetable/ui/timetable_page.dart';
import 'package:seu_timetable/ui/today_page.dart';

void main() {
  test('奶蛋优先选空位，四周有课时回到上沿，边界内显示', () {
    const course = Rect.fromLTWH(100, 100, 40, 100);
    const bounds = Size(300, 400);
    final above = naiEggPlacement(course, [course], bounds);
    expect(above.bottom, lessThanOrEqualTo(course.top + 2));
    const top = Rect.fromLTWH(100, 50, 40, 50);
    final left = naiEggPlacement(course, [course, top], bounds);
    expect(left.right, lessThanOrEqualTo(course.left + 2));
    const l = Rect.fromLTWH(60, 100, 40, 100);
    final right = naiEggPlacement(course, [course, top, l], bounds);
    expect(right.left, greaterThanOrEqualTo(course.right - 2));
    const r = Rect.fromLTWH(140, 100, 40, 100);
    final below = naiEggPlacement(course, [course, top, l, r], bounds);
    expect(below.top, greaterThanOrEqualTo(course.bottom - 2));
    const bottom = Rect.fromLTWH(100, 200, 40, 50);
    final fallback = naiEggPlacement(course, [
      course,
      top,
      l,
      r,
      bottom,
    ], bounds);
    expect(fallback, above);
    final edge = naiEggPlacement(const Rect.fromLTWH(0, 0, 20, 20), [
      const Rect.fromLTWH(0, 0, 300, 400),
    ], bounds);
    expect(edge.left, greaterThanOrEqualTo(0));
    expect(edge.top, greaterThanOrEqualTo(0));
  });

  test('新主题、显示模式、动效分别持久保存', () async {
    final dir = await Directory.systemTemp.createTemp('nai-settings-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = AppearanceController(File('${dir.path}/appearance.txt'));
    addTearDown(settings.dispose);
    await settings.setTheme(MeikeTheme.naiFamily);
    await settings.setMode(ThemeMode.dark);
    await settings.setMotion(false);
    await settings.load();
    expect(settings.theme, MeikeTheme.naiFamily);
    expect(settings.mode, ThemeMode.dark);
    expect(settings.motion, false);
  });

  for (final brightness in Brightness.values) {
    testWidgets('奶家 $brightness 小屏真实课程探头，课间与其他周不显示', (tester) async {
      final dir = Directory.systemTemp.createTempSync('nai-table-');
      final store = ScheduleStore(File('${dir.path}/schedule.json'));
      addTearDown(() {
        store.dispose();
        dir.deleteSync(recursive: true);
      });
      var now = DateTime.parse('2026-10-14T10:00:00+08:00');
      final semester = Semester(
        startDate: DateTime.parse('2026-10-12'),
        weekCount: 2,
        useSchoolCalendar: false,
      );
      await tester.runAsync(
        () => store.replace(
          ScheduleData(
            semester: semester,
            courses: [
              Course(
                name: '大数据处理',
                meetings: [
                  WeeklyMeeting(
                    weekday: 3,
                    startPeriod: 3,
                    endPeriod: 4,
                    endWeek: 2,
                    location: '教三-304',
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: meikeTheme(brightness, MeikeTheme.naiFamily),
          home: Scaffold(
            body: TimetablePage(store: store, clock: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nai-active-egg')), findsOneWidget);
      expect(find.byKey(const ValueKey('timetable-period-13')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('nai-active-egg')));
      await tester.pumpAndSettle();
      expect(find.text('上课地点'), findsOneWidget);
      expect(find.text('教三-304'), findsWidgets);
      Navigator.of(tester.element(find.text('上课地点'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nai-active-egg')), findsNothing);
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      now = DateTime.parse('2026-10-14T10:37:00+08:00');
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nai-active-egg')), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          theme: meikeTheme(brightness, MeikeTheme.naiFamily),
          home: Scaffold(
            body: TodayPage(store: store, clock: () => now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('今日进度 · 0 / 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
