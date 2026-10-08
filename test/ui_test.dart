import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/today_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  late Directory dir;
  late ScheduleStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seu-ui-');
    store = ScheduleStore(File('${dir.path}/schedule.json'));
    await store.load();
    final semester = Semester(startDate: SchoolClock.monday(DateTime.now()));
    await store.replace(
      ScheduleData(semester: semester, courses: ScheduleData.demo(semester)),
    );
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> screen(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeuTimetableApp(store: store));
    await tester.pumpAndSettle();
  }

  testWidgets('七天13节首屏、单节体育地点、无本周和放大按钮', (tester) async {
    await screen(tester);
    expect(find.text('周日'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('体育馆2楼'), findsOneWidget);
    expect(find.text('体育'), findsOneWidget);
    expect(find.text('本周'), findsNothing);
    expect(find.byTooltip('放大'), findsNothing);
    expect(
      tester.getRect(find.text('体育馆2楼')).bottom,
      lessThan(tester.getRect(find.byType(NavigationBar)).top),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('小屏和横屏布局不溢出', (tester) async {
    await screen(tester, width: 320, height: 568);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('新增课程一次选周一周四，保存后确有两条安排', (tester) async {
    await screen(tester);
    await tester.tap(find.byTooltip('添加课程').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '课程名称（必填）'),
      '一周两次测试',
    );
    await tester.ensureVisible(find.text('添加每周上课时间（可选多天）'));
    await tester.tap(find.text('添加每周上课时间（可选多天）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '周四'));
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('保存'));
      for (var i = 0; i < 100 && store.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(store.busy, isFalse);
    expect(
      store.data.courses
          .firstWhere((c) => c.name == '一周两次测试')
          .meetings
          .map((m) => m.weekday),
      [1, 4],
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('设置页直接进入学期设置，没有课间名称展示区', (tester) async {
    await screen(tester);
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(find.text('学期与作息'), findsOneWidget);
    expect(find.text('课间'), findsNothing);
    expect(find.text('学期 / 节次设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('今天倒计时按当前节次、下课铃后切换休息', (tester) async {
    var now = SchoolClock.instant(2026, 9, 21, 10, 34, 59);
    await tester.runAsync(
      () => store.replace(
        ScheduleData(
          semester: Semester(startDate: SchoolClock.instant(2026, 9, 21)),
          courses: [
            Course(
              name: '网络',
              meetings: [WeeklyMeeting(startPeriod: 3, endPeriod: 5)],
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh', 'CN')],
        locale: const Locale('zh', 'CN'),
        home: Scaffold(
          body: TodayPage(store: store, clock: () => now),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('0 分 01 秒'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('休息一下'), findsOneWidget);
    expect(find.text('0 分 01 秒'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
