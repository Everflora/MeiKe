import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/theme.dart';
import 'package:seu_timetable/ui/timetable_page.dart';

void main() {
  for (final design in MeikeTheme.values) {
    testWidgets('$design 左滑下一周右滑上一周，有动画且不越界', (tester) async {
      final dir = Directory.systemTemp.createTempSync('meike-swipe-');
      final store = ScheduleStore(File('${dir.path}/schedule.json'));
      addTearDown(() {
        store.dispose();
        dir.deleteSync(recursive: true);
      });
      await tester.runAsync(
        () => store.replace(
          ScheduleData(
            semester: Semester(
              startDate: SchoolClock.monday(DateTime.now()),
              weekCount: 2,
              useSchoolCalendar: false,
            ),
            courses: [
              Course(name: '测试课程', meetings: [WeeklyMeeting(endWeek: 2)]),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: meikeTheme(Brightness.light, design),
          home: Scaffold(body: TimetablePage(store: store)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.drag(find.byType(TimetablePage), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.drag(find.byType(TimetablePage), const Offset(-120, 0));
      await tester.pump();
      expect(find.byType(SlideTransition), findsWidgets);
      final nextPage = find.byKey(const ValueKey(2));
      final incoming = tester.widget<SlideTransition>(
        find.ancestor(of: nextPage, matching: find.byType(SlideTransition)).first,
      );
      expect(incoming.position.value.dx, greaterThan(0));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.drag(find.byType(TimetablePage), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.drag(find.byType(TimetablePage), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.tap(find.text('测试课程'));
      await tester.pumpAndSettle();
      expect(find.text('上课地点'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
