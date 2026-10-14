import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/nai_egg_pet.dart';
import 'package:seu_timetable/ui/settings_page.dart';
import 'package:seu_timetable/ui/theme.dart';

Offset eggPoint(WidgetTester tester) {
  final rect = tester.getRect(find.byKey(const ValueKey('nai-pet-egg')));
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  return Offset(math.min(rect.center.dx, width - 20), rect.center.dy);
}

Future<void> openPet(WidgetTester tester) async {
  await tester.tapAt(eggPoint(tester));
  await tester.pumpAndSettle();
}

Future<void> petSelect(WidgetTester tester, int index) async {
  await openPet(tester);
  await tester.tap(find.byKey(ValueKey('nai-pet-destination-$index')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('半身贴边不挡普通点击，可拖动，弹跳时有两轮安迪口型和五个入口', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = 0, destination = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: meikeTheme(Brightness.light, MeikeTheme.naiFamily),
        home: Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: TextButton(
                  onPressed: () => tapped++,
                  child: const Text('页面内容'),
                ),
              ),
            ),
            NaiEggCompanion(onSelect: (value) => destination = value),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final dock = tester.getRect(find.byKey(const ValueKey('nai-pet-egg')));
    expect(dock.right, greaterThan(320));
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsNothing);
    await tester.tap(find.text('页面内容'));
    expect(tapped, 1);
    await tester.dragFrom(eggPoint(tester), const Offset(0, -70));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const ValueKey('nai-pet-egg'))).top,
      lessThan(dock.top - 40),
    );
    await tester.tapAt(eggPoint(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).frame, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).frame, 2);
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).frame, 1);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).frame, 2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      if (i > 0) await openPet(tester);
      await tester.tap(find.byKey(ValueKey('nai-pet-destination-$i')));
      await tester.pumpAndSettle();
      expect(destination, i);
      expect(find.byKey(const ValueKey('nai-pet-menu')), findsNothing);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('深色横屏菜单可滚动，减弱动态时直接展开，点空白收起', (tester) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: meikeTheme(Brightness.dark, MeikeTheme.naiFamily),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: const TextScaler.linear(1.6),
          ),
          child: child!,
        ),
        home: NaiEggCompanion(onSelect: (_) {}),
      ),
    );
    await openPet(tester);
    expect(tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).frame, 0);
    await tester.ensureVisible(
      find.byKey(const ValueKey('nai-pet-destination-4')),
    );
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  late Directory dir;
  late ScheduleStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('nai-pet-app-');
    store = ScheduleStore(File('${dir.path}/schedule.json'));
    await store.replace(
      ScheduleData(
        semester: Semester(
          startDate: SchoolClock.monday(DateTime.now()),
          useSchoolCalendar: false,
        ),
        courses: [
          Course(
            name: '测试课程',
            location: '教三-304',
            meetings: [WeeklyMeeting(startPeriod: 3, endPeriod: 4)],
          ),
        ],
      ),
    );
    await File(
      '${dir.path}/appearance.txt',
    ).writeAsString('{"theme":"naiFamily","mode":"light","motion":false}');
  });
  tearDown(() async {
    store.dispose();
    await dir.delete(recursive: true);
  });
  Future<void> app(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(SeuTimetableApp(store: store));
      await Future<void>.delayed(const Duration(milliseconds: 70));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('宠物导航切换真实主页，从课程详情返回，系统返回先收起菜单', (tester) async {
    await app(tester);
    await petSelect(tester, 1);
    expect(find.byKey(const ValueKey('nai-today-headline')), findsOneWidget);
    await petSelect(tester, 0);
    await tester.tap(find.text('测试课程'));
    await tester.pumpAndSettle();
    expect(find.text('上课地点'), findsOneWidget);
    await petSelect(tester, 4);
    expect(find.text('上课地点'), findsNothing);
    expect(find.text('学期与作息'), findsOneWidget);
    await openPet(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsNothing);
    expect(find.text('学期与作息'), findsOneWidget);
    await petSelect(tester, 2);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName.endsWith(
              'discussion-circle.webp',
            ),
      ),
      findsOneWidget,
    );
    await petSelect(tester, 3);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName.endsWith('chicken-garden.webp'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('未保存编辑通过原确认流程，取消保留草稿，确认后跳到目标主页', (tester) async {
    await app(tester);
    await tester.tap(find.byTooltip('添加课程'));
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextFormField, '课程名称（必填）');
    await tester.enterText(name, '未保存课程');
    FocusManager.instance.primaryFocus?.unfocus();
    await petSelect(tester, 1);
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('未保存课程'), findsOneWidget);
    expect(store.data.courses.length, 1);
    await petSelect(tester, 1);
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nai-today-headline')), findsOneWidget);
    expect(store.data.courses.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('宠物开关独立保存，主题切换和键盘出现时隐藏', (tester) async {
    await app(tester);
    addTearDown(tester.view.resetViewInsets);
    await petSelect(tester, 4);
    final settings = tester
        .widget<SettingsPage>(find.byType(SettingsPage))
        .appearance!;
    expect(find.byType(NaiEggCompanion), findsOneWidget);
    await tester.runAsync(() => settings.setEggPet(false));
    await tester.pumpAndSettle();
    expect(find.byType(NaiEggCompanion), findsNothing);
    await tester.runAsync(() => settings.load());
    expect(settings.eggPet, false);
    await tester.runAsync(() => settings.setEggPet(true));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(find.byType(NaiEggCompanion), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await tester.runAsync(() => settings.setTheme(MeikeTheme.plum));
    await tester.pumpAndSettle();
    expect(find.byType(NaiEggCompanion), findsNothing);
    expect(settings.eggPet, true);
    await tester.pumpWidget(const SizedBox());
  });
}
