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
import 'package:seu_timetable/ui/nai_today.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('黄色状态卡在小屏下保留上课、无课、下课三种设计和真实节数 $brightness', (tester) async {
      final dir = Directory.systemTemp.createTempSync('nai-today-states-');
      final store = ScheduleStore(File('${dir.path}/schedule.json'));
      addTearDown(() {
        store.dispose();
        dir.deleteSync(recursive: true);
      });
      await tester.runAsync(
        () => store.replace(
          ScheduleData(
            semester: Semester(
              startDate: SchoolClock.instant(2026, 9, 21),
              useSchoolCalendar: false,
            ),
            courses: [
              Course(
                name: '计算机网络',
                location: '教三-402',
                meetings: [
                  WeeklyMeeting(weekday: 4, startPeriod: 3, endPeriod: 5),
                ],
              ),
              Course(
                name: '批判性思维',
                meetings: [
                  WeeklyMeeting(weekday: 4, startPeriod: 6, endPeriod: 7),
                ],
              ),
              Course(
                name: '大数据处理',
                meetings: [
                  WeeklyMeeting(weekday: 4, startPeriod: 8, endPeriod: 9),
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
      for (final scale in [1.0, 1.6]) {
        for (final scenario in [
          (SchoolClock.instant(2026, 10, 15, 10, 12), '今日份开机', 'naiwa-front'),
          (SchoolClock.instant(2026, 10, 15, 17, 30), '今日份完成', 'naiwa-back'),
          (SchoolClock.instant(2026, 10, 17, 10), '今日份放空', 'naidan'),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: meikeTheme(brightness, MeikeTheme.naiFamily),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: NaiTodayContent(store: store, now: scenario.$1),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(scenario.$2), findsOneWidget);
          final card = tester.widget<ColoredBox>(
            find.byKey(const ValueKey('nai-today-gold-card')),
          );
          expect(card.color, naiTodayGold);
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is Image &&
                  w.image is AssetImage &&
                  (w.image as AssetImage).assetName.endsWith(
                    '${scenario.$3}.webp',
                  ),
            ),
            findsOneWidget,
          );
          if (scenario.$2 == '今日份开机') {
            expect(find.text('23'), findsOneWidget);
            expect(find.text('本节 10:35 下课'), findsOneWidget);
            expect(find.text('本次连堂课 12:15 结束'), findsOneWidget);
          }
          if (scenario.$2 == '今日份完成') {
            expect(find.text('今天7节课全部结束\n下一站食堂'), findsOneWidget);
          }
          expect(
            tester.getRect(find.byKey(const ValueKey('nai-today-copy'))).bottom,
            lessThan(
              tester
                  .getRect(find.byKey(const ValueKey('nai-today-footer')))
                  .top,
            ),
          );
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

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
      final border = tester.widget<Material>(
        find.byKey(const ValueKey('nai-active-course-border')),
      );
      expect((border.shape! as RoundedRectangleBorder).side.width, 2);
      expect(find.byKey(const ValueKey('nai-add-eye-5.0')), findsOneWidget);
      expect(find.byKey(const ValueKey('nai-add-eye-15.0')), findsOneWidget);
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
      expect(find.text('今日份缓冲'), findsOneWidget);
      expect(find.byKey(const ValueKey('nai-today-gold-card')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
