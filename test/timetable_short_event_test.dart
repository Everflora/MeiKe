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
    for (final duration in [1, 15, 30]) {
      testWidgets('$design 小屏 $duration 分钟安排不溢出，可查看完整地点和时间', (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'meike-short-card-',
        );
        final store = ScheduleStore(File('${directory.path}/schedule.json'));
        addTearDown(() {
          store.dispose();
          directory.deleteSync(recursive: true);
        });
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.runAsync(
          () => store.replace(
            ScheduleData(
              semester: Semester(
                startDate: SchoolClock.monday(DateTime.now()),
                weekCount: 1,
                useSchoolCalendar: false,
              ),
              courses: [
                Course(
                  name: '课程',
                  extras: [
                    ExtraMeeting(
                      title: '签到',
                      week: 1,
                      weekday: 1,
                      startMinute: 490,
                      endMinute: 490 + duration,
                      location: '教三301',
                    ),
                    ExtraMeeting(
                      title: '相邻安排',
                      week: 1,
                      weekday: 1,
                      startMinute: 490 + duration,
                      endMinute: 530,
                      location: '教三302',
                    ),
                  ],
                ),
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
        final first = find.byWidgetPredicate(
          (w) =>
              w is Semantics && (w.properties.label?.contains('签到') ?? false),
        );
        final second = find.byWidgetPredicate(
          (w) =>
              w is Semantics && (w.properties.label?.contains('相邻安排') ?? false),
        );
        expect(first, findsOneWidget);
        expect(second, findsOneWidget);
        expect(
          tester.getRect(first).bottom,
          lessThanOrEqualTo(tester.getRect(second).top),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(first);
        await tester.pumpAndSettle();
        expect(find.text('上课地点'), findsOneWidget);
        expect(find.text('教三301'), findsWidgets);
        expect(
          find.text('周一 · 08:10–${LessonPeriod.format(490 + duration)}'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
