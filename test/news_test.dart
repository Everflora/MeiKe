import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/news_store.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';

import 'fixtures/appearance.dart';

Json row(String id, {String enrollment = '10/20', String deadline = '明天'}) => {
  'itemId': 'demo',
  'offeringId': id,
  'name': '演示劳动课程 $id',
  'category': '校园劳动',
  'location': '九龙湖',
  'time': '2026-10-12 10:00',
  'deadline': deadline,
  'enrollment': enrollment,
  'teacher': '示例教师',
};

void main() {
  late Directory dir;
  late NewsStore news;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('meike-news-');
    news = NewsStore(File('${dir.path}/news.json'));
  });
  tearDown(() async {
    news.dispose();
    await dir.delete(recursive: true);
  });

  test('首次建立列表，后续新增标记且状态变化不会重复新增，重启保留', () async {
    expect(await news.sync([row('a')]), 0);
    expect(news.items.single.unread, isFalse);
    expect(await news.sync([row('a', enrollment: '已满'), row('b')]), 1);
    expect(
      news.items.firstWhere((i) => i.field('offeringId') == 'a').selectable,
      isFalse,
    );
    final fresh = news.items.firstWhere((i) => i.field('offeringId') == 'b');
    expect(fresh.unread, isTrue);
    await news.markRead(fresh.id);
    final reopened = NewsStore(news.file);
    await reopened.load();
    expect(reopened.items.length, 2);
    expect(reopened.items.every((i) => !i.unread), isTrue);
    expect(reopened.updated, news.updated);
    reopened.dispose();
  });
  test('满额、截止及移出列表不能显示为可选，空列表是有效同步', () async {
    await news.sync([row('a'), row('b', deadline: '已截止')]);
    expect(news.items.where((i) => i.selectable).length, 1);
    await news.sync([]);
    expect(news.items.every((i) => !i.present && !i.selectable), isTrue);
    expect(news.updated, isNotNull);
  });
  test('同名同时间的不同开课 ID 不合并；没有 ID 时使用完整课程身份', () async {
    await news.sync([
      row('a'),
      {...row('b'), 'name': row('a')['name']},
    ]);
    expect(news.items.where((i) => i.present).length, 2);
    await news.sync([
      {...row('a'), 'offeringId': '', 'location': '校区甲'},
      {...row('a'), 'offeringId': '', 'location': '校区乙'},
    ]);
    expect(news.items.where((i) => i.present).length, 2);
  });
  test('异常和重复课程不覆盖原缓存，损坏缓存同步恢复前保留副本', () async {
    await news.sync([row('a')]);
    final original = await news.file.readAsString();
    await expectLater(news.sync([row('a'), row('a')]), throwsFormatException);
    await expectLater(
      news.sync([
        {...row('a'), 'name': null},
      ]),
      throwsFormatException,
    );
    expect(await news.file.readAsString(), original);
    await news.file.writeAsString('broken-cache');
    await news.load();
    expect(news.writable, isFalse);
    await news.sync([row('b')]);
    expect(news.writable, isTrue);
    final backup = dir.listSync().whereType<File>().firstWhere(
      (f) => f.path.contains('.unreadable-'),
    );
    expect(await backup.readAsString(), 'broken-cache');
    expect(jsonDecode(await news.file.readAsString())['version'], 1);
  });
  test('劳动教育读取只允许学校 HTTPS 指定页面', () {
    expect(isLaborNewsUrl(Uri.parse(laborNewsUrl)), isTrue);
    expect(
      isLaborNewsUrl(
        Uri.parse('https://webvpn.seu.edu.cn/proxy/SJItemKaiKe/XuanKe/Index'),
      ),
      isTrue,
    );
    expect(
      isLaborNewsUrl(
        Uri.parse('http://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index'),
      ),
      isFalse,
    );
    expect(
      isLaborNewsUrl(
        Uri.parse('https://seu.edu.cn.evil.example/SJItemKaiKe/XuanKe/Index'),
      ),
      isFalse,
    );
    expect(isLaborNewsUrl(Uri.parse('https://auth.seu.edu.cn/login')), isFalse);
  });
  testWidgets('320 像素小屏新增新闻导航，离线空态及设置入口不溢出', (tester) async {
    late ScheduleStore schedule;
    await tester.runAsync(() async {
      schedule = ScheduleStore(File('${dir.path}/schedule.json'));
      await schedule.load();
      await savePlumTheme(dir);
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await tester.pumpWidget(SeuTimetableApp(store: schedule));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '校园'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('劳动教育'), findsOneWidget);
    expect(find.text('登录并同步劳动教育'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '我的'));
    await tester.pumpAndSettle();
    expect(find.text('学期 / 节次设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    schedule.dispose();
  });
}
