import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/school_import.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/lecture_selection_page.dart';
import 'package:seu_timetable/ui/news_page.dart';
import 'package:seu_timetable/ui/theme.dart';

void main() {
  test('素质讲座入口使用指定学校HTTPS路径，沿用学校登录导航', () {
    final url = Uri.parse(lectureSelectionUrl);
    expect(url.host, 'ehall.seu.edu.cn');
    expect(url.path, '/gsapp/sys/yddjzxxtjappseu/*default/index.do');
    expect(schoolNavigationTarget(url), url);
    expect(
      schoolNavigationTarget(
        Uri.parse('https://auth.seu.edu.cn/authserver/login'),
      ),
      isNotNull,
    );
    expect(
      schoolNavigationTarget(Uri.parse('https://seu.edu.cn.example.com/')),
      isNull,
    );
    expect(schoolNavigationTarget(Uri.parse('javascript:alert(1)')), isNull);
  });

  for (final design in MeikeTheme.values) {
    testWidgets('$design 新闻可进入素质讲座并返回劳动教育，小屏大字不溢出', (tester) async {
      final dir = Directory.systemTemp.createTempSync('meike-lecture-');
      final store = ScheduleStore(File('${dir.path}/schedule.json'));
      addTearDown(() {
        store.dispose();
        dir.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final scale in [1.0, 1.7]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: meikeTheme(Brightness.light, design),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: NewsPage(key: ValueKey(scale), store: store),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('素质讲座'));
        await tester.pumpAndSettle();
        expect(find.text('素质讲座选课'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '进入素质讲座选课'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('劳动教育'));
        await tester.pumpAndSettle();
        expect(find.text('劳动教育课程'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
