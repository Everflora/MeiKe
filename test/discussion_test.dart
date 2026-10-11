import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/discussion_client.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';

void main() {
  test('匹配只上传课程名、教师和实际教学周时间，不上传备注或群号', () {
    final course = Course(
      name: ' 演示课程 ',
      teacher: ' 示例教师 ',
      notes: '私人备注',
      location: '教室甲',
      schoolClass: SchoolClass(
        termCode: 'demo-term',
        courseCode: 'DEMO',
        classId: 'CLASS-A',
        classNumber: '01',
      ),
      meetings: [
        WeeklyMeeting(
          weekday: 4,
          startPeriod: 3,
          endPeriod: 4,
          startWeek: 3,
          endWeek: 9,
          pattern: WeekPattern.odd,
        ),
      ],
    );
    final request = discussionMatchRequest(course, 'selected-term');
    expect(
      request.keys,
      unorderedEquals(['termCode', 'name', 'teacher', 'meetings']),
    );
    expect(request['termCode'], 'selected-term');
    expect(request['name'], '演示课程');
    expect((request['meetings'] as List).single['weeks'], [3, 5, 7, 9]);
    expect((request['meetings'] as List).single['weekday'], 4);
    expect(request.containsKey('schoolClass'), isFalse);
  });

  test('前后阶段时间分别发送，不放宽节次或周次', () {
    final request = discussionMatchRequest(
      Course(
        name: '演示课程',
        teacher: '示例教师',
        meetings: [
          WeeklyMeeting(
            weekday: 4,
            startPeriod: 3,
            endPeriod: 5,
            startWeek: 1,
            endWeek: 8,
          ),
          WeeklyMeeting(
            weekday: 4,
            startPeriod: 4,
            endPeriod: 5,
            startWeek: 9,
            endWeek: 16,
          ),
        ],
      ),
      'term',
    );
    final meetings = request['meetings'] as List;
    expect(meetings.length, 2);
    expect(meetings.first['endPeriod'], 5);
    expect(meetings.last['startPeriod'], 4);
    expect(meetings.last['weeks'], List.generate(8, (i) => i + 9));
  });

  test('缺教师或每周时间时不发起模糊匹配', () {
    expect(
      () => discussionMatchRequest(Course(name: '演示课程'), 'term'),
      throwsFormatException,
    );
    expect(
      () =>
          discussionMatchRequest(Course(name: '演示课程', teacher: '示例教师'), 'term'),
      throwsFormatException,
    );
  });

  testWidgets('讨论室在底部导航，小屏打开和取消昵称不影响离线课表', (tester) async {
    late Directory dir;
    late ScheduleStore store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('seu-discussion-ui-');
      store = ScheduleStore(File('${dir.path}/schedule.json'));
      await store.load();
    });
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeuTimetableApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, '讨论'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('设置头像和昵称'), findsOneWidget);
    await tester.tap(find.text('设置头像和昵称'));
    await tester.pumpAndSettle();
    expect(find.text('选择头像'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
    });
    store.dispose();
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
