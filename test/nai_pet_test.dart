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
  return Offset(rect.center.dx.clamp(20.0, width - 20), rect.center.dy);
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
  testWidgets('贴边不挡点击，先站稳再连续开口，五个圆形气泡环绕奶蛋', (tester) async {
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
    final egg = find.byKey(const ValueKey('nai-pet-egg'));
    final dock = tester.getRect(egg);
    expect(dock.right, greaterThan(320));
    await tester.tap(find.text('页面内容'));
    expect(tapped, 1);
    await tester.dragFrom(eggPoint(tester), const Offset(0, -70));
    await tester.pumpAndSettle();
    expect(tester.getRect(egg).top, lessThan(dock.top - 40));
    await tester.tapAt(eggPoint(tester));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final landed = tester.getRect(egg);
    expect(
      tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).mouthProgress,
      0,
    );
    await tester.pump(const Duration(milliseconds: 110));
    expect(tester.getRect(egg), landed);
    expect(
      tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).mouthProgress,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    final center = tester.getRect(egg).center;
    final bubbles = [
      for (var i = 0; i < 5; i++)
        tester.getRect(find.byKey(ValueKey('nai-pet-destination-$i'))),
    ];
    final radius = (bubbles.first.center - center).distance;
    for (var i = 0; i < 5; i++) {
      final bubble = bubbles[i];
      expect(bubble.width, bubble.height);
      expect((bubble.center - center).distance, closeTo(radius, .01));
      expect(bubble.left, greaterThanOrEqualTo(0));
      expect(bubble.right, lessThanOrEqualTo(320));
      for (var j = i + 1; j < 5; j++) {
        expect(bubble.overlaps(bubbles[j]), false);
      }
      expect(
        tester
            .widget<Material>(find.byKey(ValueKey('nai-pet-bubble-$i')))
            .shape,
        isA<CircleBorder>(),
      );
      expect(
        tester
            .widget<Material>(find.byKey(ValueKey('nai-pet-bubble-$i')))
            .color,
        isNot(Colors.white),
      );
    }
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

  testWidgets('横屏深色大字下气泡全部可见，减弱动态时直接展开，点空白收起', (tester) async {
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
    expect(
      tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).mouthProgress,
      0,
    );
    for (var i = 0; i < 5; i++) {
      final rect = tester.getRect(
        find.byKey(ValueKey('nai-pet-destination-$i')),
      );
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(320));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(568));
      final color = tester
          .widget<Material>(find.byKey(ValueKey('nai-pet-bubble-$i')))
          .color!;
      expect(color.computeLuminance(), lessThan(.1));
    }
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('站稳后口型有连续逐帧过渡，身体不摇摆，收回和途中变向不跳位', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<NaiEggCompanionState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: meikeTheme(Brightness.light, MeikeTheme.naiFamily),
        home: NaiEggCompanion(key: key, onSelect: (_) {}),
      ),
    );
    final egg = find.byKey(const ValueKey('nai-pet-egg'));
    final dock = tester.getRect(egg);
    key.currentState!.reveal();
    await tester.pump();
    var previousX = dock.left;
    var runs = 0, wasOpen = false;
    Rect? landed;
    final mouthValues = <double>{};
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final rect = tester.getRect(egg);
      expect(rect.left, lessThanOrEqualTo(previousX + .01));
      final mouth = tester
          .widget<NaiEggSprite>(find.byType(NaiEggSprite))
          .mouthProgress;
      if (i < 29) expect(mouth, 0);
      if (i >= 25) {
        landed ??= rect;
        expect(rect, landed);
        final transform = tester.widget<Transform>(
          find.descendant(of: egg, matching: find.byType(Transform)).first,
        );
        expect(
          math.atan2(
            transform.transform.storage[1],
            transform.transform.storage[0],
          ),
          closeTo(0, .00001),
        );
      }
      if (mouth > 0) mouthValues.add(mouth);
      if (mouth > 0 && !wasOpen) runs++;
      wasOpen = mouth > 0;
      previousX = rect.left;
    }
    expect(runs, 1);
    expect(wasOpen, false);
    expect(mouthValues.length, greaterThan(25));
    final open = tester.getRect(egg);
    await tester.pump(const Duration(seconds: 8));
    expect(tester.getRect(egg), open);
    expect(tester.binding.hasScheduledFrame, false);
    key.currentState!.dismiss();
    await tester.pump();
    expect(tester.getRect(egg).topLeft, open.topLeft);
    await tester.pump(const Duration(milliseconds: 90));
    final returning = tester.getRect(egg);
    expect(returning.left, greaterThan(open.left));
    expect(returning.left, lessThan(dock.left));
    expect(
      tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).mouthProgress,
      0,
    );
    key.currentState!.reveal();
    await tester.pump();
    expect(tester.getRect(egg).topLeft, returning.topLeft);
    await tester.pumpAndSettle();
    key.currentState!.dismiss();
    await tester.pump();
    previousX = tester.getRect(egg).left;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      final rect = tester.getRect(egg);
      expect(rect.left, greaterThanOrEqualTo(previousX - .01));
      expect(rect.left, lessThanOrEqualTo(dock.left));
      expect(
        tester.widget<NaiEggSprite>(find.byType(NaiEggSprite)).mouthProgress,
        0,
      );
      previousX = rect.left;
    }
    expect(tester.getRect(egg), dock);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('可左右拖动，中间松手回起点，靠边释放分别吸附左边和右边，取消拖动也回起点', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: meikeTheme(Brightness.light, MeikeTheme.naiFamily),
        home: NaiEggCompanion(onSelect: (_) {}),
      ),
    );
    final egg = find.byKey(const ValueKey('nai-pet-egg'));
    final dock = tester.getRect(egg);
    var gesture = await tester.startGesture(eggPoint(tester));
    await gesture.moveBy(const Offset(-90, -30));
    await tester.pump();
    await gesture.moveBy(const Offset(-70, 0));
    await tester.pump();
    expect(tester.getRect(egg).center.dx, inExclusiveRange(80, 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(egg), dock);
    await tester.dragFrom(eggPoint(tester), const Offset(-350, -60));
    await tester.pumpAndSettle();
    final left = tester.getRect(egg);
    expect(left.center.dx, 0);
    expect(left.center.dy, lessThan(dock.center.dy));
    await openPet(tester);
    final open = tester.getRect(egg);
    gesture = await tester.startGesture(eggPoint(tester));
    await gesture.moveBy(const Offset(70, 50));
    await tester.pump();
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(egg), open);
    expect(find.byKey(const ValueKey('nai-pet-menu')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(tester.getRect(egg), left);
    gesture = await tester.startGesture(eggPoint(tester));
    await gesture.moveBy(const Offset(140, 30));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.getRect(egg), left);
    await tester.dragFrom(eggPoint(tester), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(egg).center.dx, 390);
    expect(tester.takeException(), isNull);
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
    await tester.dragFrom(eggPoint(tester), const Offset(-350, -40));
    await tester.pumpAndSettle();
    final companion = tester.state<NaiEggCompanionState>(
      find.byType(NaiEggCompanion),
    );
    final dock = tester.getRect(find.byKey(const ValueKey('nai-pet-egg')));
    expect(dock.center.dx, 0);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(find.byType(NaiEggCompanion), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(
      tester.state<NaiEggCompanionState>(find.byType(NaiEggCompanion)),
      same(companion),
    );
    expect(tester.getRect(find.byKey(const ValueKey('nai-pet-egg'))), dock);
    await tester.runAsync(() => settings.setTheme(MeikeTheme.plum));
    await tester.pumpAndSettle();
    expect(find.byType(NaiEggCompanion), findsNothing);
    expect(settings.eggPet, true);
    await tester.pumpWidget(const SizedBox());
  });
}
