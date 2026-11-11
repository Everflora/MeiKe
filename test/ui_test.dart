import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/today_page.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/theme.dart';
import 'package:seu_timetable/ui/settings_page.dart';
import 'package:seu_timetable/ui/timetable_page.dart';
import 'package:seu_timetable/data/jwc_news.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'fixtures/appearance.dart';

void main() {
  late Directory dir;
  late ScheduleStore store;
  Finder finalPeriodLabel() => find.descendant(
    of: find.byKey(const ValueKey('timetable-period-13')),
    matching: find.text('13'),
  );
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
    // File I/O completes on the real clock, outside the widget fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(SeuTimetableApp(store: store));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('主题与显示模式分两行，银杏切换全局并在重启后保留', (tester) async {
    await tester.runAsync(() => savePlumTheme(dir));
    await screen(tester);
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.ensureVisible(find.byTooltip('选择主题'));
      await tester.tap(find.byTooltip('选择主题'));
      await tester.pumpAndSettle();
      expect(find.text('银杏'), findsOneWidget);
      expect(find.text('浅色'), findsNothing);
      await tester.tap(find.text('银杏'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();
    expect(
      tester.widget<SettingsPage>(find.byType(SettingsPage)).appearance!.theme,
      MeikeTheme.ginkgo,
    );
    final settingsContext = tester.element(find.text('显示模式'));
    expect(settingsContext.meike.design, MeikeTheme.ginkgo);
    await tester.runAsync(() async {
      await tester.ensureVisible(find.byTooltip('选择显示模式'));
      await tester.tap(find.byTooltip('选择显示模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    });
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('显示模式'))).brightness,
      Brightness.dark,
    );
    expect(tester.element(find.text('显示模式')).meike.design, MeikeTheme.ginkgo);
    await tester.pumpWidget(const SizedBox());
    await screen(tester, width: 320, height: 568);
    expect(tester.element(find.text('体育')).meike.design, MeikeTheme.ginkgo);
    expect(
      Theme.of(tester.element(find.text('体育'))).brightness,
      Brightness.dark,
    );
    expect(find.text('体育馆2楼'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('银杏布局有品牌顶栏、独立周次面板和悬浮底栏；青梅不变', (tester) async {
    final appearance = AppearanceController(File('${dir.path}/appearance.txt'));
    await tester.runAsync(() async {
      await appearance.setTheme(MeikeTheme.ginkgo);
      await appearance.setMode(ThemeMode.light);
    });
    appearance.dispose();
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.resetPadding);
    await screen(tester);
    expect(find.byKey(const ValueKey('ginkgo-brand-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('ginkgo-calendar-panel')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ginkgo-floating-navigation')),
      findsOneWidget,
    );
    expect(find.text('MEIKE · SOUTHEAST'), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(TimetablePage),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      MeikeColors.ginkgoLight.paper,
    );
    final panel = tester.getRect(
      find
          .descendant(
            of: find.byKey(const ValueKey('ginkgo-calendar-panel')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final header = tester.getRect(
      find.byKey(const ValueKey('ginkgo-brand-header')),
    );
    expect(panel.top, greaterThan(header.bottom));
    expect(panel.left, greaterThan(header.left));
    expect(tester.getRect(find.byTooltip('选择教学周')).top, greaterThan(panel.top));
    expect(tester.getRect(find.byTooltip('添加课程')).bottom, lessThan(panel.top));
    expect(
      tester.getRect(finalPeriodLabel()).bottom,
      lessThan(tester.getRect(find.byType(NavigationBar)).top),
    );
    expect(
      find.descendant(
        of: find.widgetWithText(NavigationDestination, '校园'),
        matching: find.byType(CampusIcon),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      final restored = AppearanceController(File('${dir.path}/appearance.txt'));
      await restored.load();
      await restored.setTheme(MeikeTheme.plum);
      restored.dispose();
    });
    await screen(tester);
    expect(find.byKey(const ValueKey('ginkgo-calendar-panel')), findsNothing);
    expect(find.text('MEIKE · SOUTHEAST'), findsNothing);
    expect(find.text('周日'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('七天13节首屏、单节体育地点、无本周和放大按钮', (tester) async {
    await tester.runAsync(() => savePlumTheme(dir));
    await screen(tester);
    expect(find.text('周日'), findsOneWidget);
    expect(finalPeriodLabel(), findsOneWidget);
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
  testWidgets('两套主题都显示完整时段，连堂分节对齐、单节地点保留，课程可点击', (tester) async {
    for (final theme in MeikeTheme.values) {
      final appearance = AppearanceController(
        File('${dir.path}/appearance.txt'),
      );
      await tester.runAsync(() async {
        await appearance.setTheme(theme);
        await appearance.setMode(ThemeMode.light);
        final semester = store.data.semester;
        await store.replace(
          ScheduleData(
            semester: semester,
            courses: [
              Course(
                name: '数据库原理',
                location: '教三-302',
                meetings: [WeeklyMeeting(startPeriod: 3, endPeriod: 5)],
              ),
              Course(
                name: '体育',
                location: '桃园田径场',
                meetings: [
                  WeeklyMeeting(weekday: 3, startPeriod: 2, endPeriod: 2),
                ],
              ),
              Course(
                name: '午间实验',
                location: '实301',
                extras: [
                  ExtraMeeting(
                    title: '午间实验',
                    weekday: 7,
                    startMinute: 780,
                    endMinute: 810,
                  ),
                ],
              ),
            ],
          ),
        );
      });
      appearance.dispose();
      await screen(tester, width: 320, height: 568);
      expect(find.text('午休'), findsNothing);
      expect(find.text('晚休'), findsNothing);
      expect(find.text('5′'), findsNothing);
      expect(find.text('9:50'), findsOneWidget);
      expect(find.text('10:35'), findsOneWidget);
      final axis = find.byKey(const ValueKey('timetable-period-3'));
      final start = find.descendant(of: axis, matching: find.text('9:50'));
      final dash = find.descendant(of: axis, matching: find.text('-'));
      final end = find.descendant(of: axis, matching: find.text('10:35'));
      expect(dash, findsOneWidget);
      final startRect = tester.getRect(start);
      final dashRect = tester.getRect(dash);
      final endRect = tester.getRect(end);
      expect(startRect.bottom, lessThanOrEqualTo(dashRect.top));
      expect(dashRect.bottom, lessThanOrEqualTo(endRect.top));
      expect(startRect.center.dx, closeTo(dashRect.center.dx, .01));
      expect(endRect.center.dx, closeTo(dashRect.center.dx, .01));
      expect(tester.getRect(axis).contains(startRect.topLeft), isTrue);
      expect(
        endRect.bottom,
        lessThanOrEqualTo(tester.getRect(axis).bottom + .01),
      );
      expect(
        endRect.right,
        lessThanOrEqualTo(tester.getRect(axis).right + .01),
      );
      expect(find.text('8:00'), findsOneWidget);
      expect(find.text('8:45'), findsOneWidget);

      expect(find.text('21:25'), findsOneWidget);
      expect(find.text('第 3–5 节'), findsOneWidget);
      expect(find.text('桃园田径场'), findsOneWidget);
      expect(find.text('午间实验 · 午间实验'), findsOneWidget);
      expect(find.text('实301'), findsOneWidget);
      expect(find.text('13:00'), findsOneWidget);
      expect(find.text('13:30'), findsOneWidget);
      final event = store.data
          .occurrences(1)
          .firstWhere((e) => e.name == '数据库原理');
      final slot4 = tester.getRect(
        find.byKey(const ValueKey('timetable-period-4')),
      );
      final slot5 = tester.getRect(
        find.byKey(const ValueKey('timetable-period-5')),
      );
      final divider4 = tester.getRect(
        find.byKey(ValueKey('course-divider-${event.id}-4')),
      );
      final divider5 = tester.getRect(
        find.byKey(ValueKey('course-divider-${event.id}-5')),
      );
      expect(divider4.top, closeTo(slot4.top, .01));
      expect(divider5.top, closeTo(slot5.top, .01));
      expect(divider5.top - divider4.top, closeTo(slot4.height, .01));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('午间实验 · 午间实验'));
      await tester.pumpAndSettle();
      expect(find.text('上课地点'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭课程详情'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('数据库原理'));
      await tester.pumpAndSettle();
      expect(find.text('上课地点'), findsOneWidget);
      expect(find.text('教三-302'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('小屏和横屏布局不溢出', (tester) async {
    await screen(tester, width: 320, height: 568);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('教务栏目首次进入、选择及失去焦点后始终显示绿色边框', (tester) async {
    for (final theme in MeikeTheme.values) {
      final appearance = AppearanceController(
        File('${dir.path}/appearance.txt'),
      );
      await tester.runAsync(() async {
        await appearance.setTheme(theme);
      });
      appearance.dispose();
      await screen(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('校园').last);
        await tester.pump();
        await tester.tap(find.text('教务通知'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      InputDecorator selector() => tester.widget<InputDecorator>(
        find.descendant(
          of: find.byType(DropdownButtonFormField<JwcSection>),
          matching: find.byType(InputDecorator),
        ),
      );
      void checkBorder() {
        final decorator = selector();
        final enabled = decorator.decoration.enabledBorder!;
        final focused = decorator.decoration.focusedBorder!;
        expect(enabled.borderSide.style, BorderStyle.solid);
        expect(enabled.borderSide.width, greaterThan(0));
        expect(enabled, focused);
        expect(
          enabled.borderSide.color,
          tester
              .element(find.byType(DropdownButtonFormField<JwcSection>))
              .meike
              .green,
        );
        expect(tester.takeException(), isNull);
      }

      expect(selector().isFocused, isFalse);
      checkBorder();
      await tester.runAsync(() async {
        await tester.tap(find.byType(DropdownButtonFormField<JwcSection>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('实践教学').last);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<JwcSection>>(
              find.byType(DropdownButtonFormField<JwcSection>),
            )
            .initialValue,
        JwcSection.practice,
      );
      checkBorder();
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(selector().isFocused, isFalse);
      checkBorder();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets('五项导航，课表与我的都可进入课程管理并返回', (tester) async {
    await tester.runAsync(() => savePlumTheme(dir));
    await screen(tester);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await tester.tap(find.byTooltip('课程管理'));
    await tester.pumpAndSettle();
    expect(find.text('所有课程'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(finalPeriodLabel(), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程管理'));
    await tester.pumpAndSettle();
    expect(find.text('所有课程'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('单节课程可打开完整地点，再进入原课程编辑流程', (tester) async {
    await screen(tester);
    await tester.tap(find.text('体育'));
    await tester.pumpAndSettle();
    expect(find.text('上课地点'), findsOneWidget);
    expect(find.text('体育馆2楼'), findsNWidgets(2));
    await tester.tap(find.text('编辑课程与上课安排'));
    await tester.pumpAndSettle();
    expect(find.text('编辑课程'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '课程名称（必填）'), findsOneWidget);
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
    await tester.tap(find.text('我的').last);
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
