import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/domain/schedule.dart';

void main() {
  late ScheduleData data;
  setUp(
    () => data = ScheduleData(
      // These fixtures test raw recurrence; calendar overrides have their own suite.
      semester: Semester(
        startDate: SchoolClock.instant(2026, 9, 21),
        useSchoolCalendar: false,
      ),
    ),
  );
  test('学校作息与课间完整匹配', () {
    expect(data.validationError(), isNull);
    expect(data.semester.periods.map((p) => p.startMinute), [
      480,
      530,
      590,
      640,
      690,
      840,
      890,
      950,
      1000,
      1050,
      1140,
      1190,
      1240,
    ]);
    expect(
      data.semester.periods.every((p) => p.endMinute - p.startMinute == 45),
      isTrue,
    );
    expect(data.breaks.length, 12);
    expect(data.breaks.first.duration, 5);
    expect(data.breaks.firstWhere((g) => g.title == '午休').duration, 105);
    expect(data.breaks.firstWhere((g) => g.title == '晚饭 / 休息').duration, 45);
  });
  test('中国时区、跨周与开学前负数周，独立于主机时区', () {
    final s = data.semester;
    expect(SchoolClock.week(SchoolClock.instant(2026, 9, 20), s), 0);
    expect(SchoolClock.week(SchoolClock.instant(2026, 9, 13), s), -1);
    expect(SchoolClock.week(DateTime.parse('2026-09-27T15:59:59Z'), s), 1);
    expect(SchoolClock.week(DateTime.parse('2026-09-27T16:00:00Z'), s), 2);
    expect(SchoolClock.weekday(DateTime.parse('2026-09-27T16:00:00Z')), 1);
    expect(SchoolClock.weekday(SchoolClock.instant(2026, 9, 27)), 7);
    expect(SchoolClock.monday(SchoolClock.instant(2026, 9, 23)), s.startDate);
    expect(SchoolClock.date(8, 7, s), SchoolClock.instant(2026, 11, 15));
    expect(SchoolClock.minute(DateTime.parse('2026-09-21T01:50:00Z')), 590);
  });
  test('多天选择生成独立安排并保持单双周和覆盖地点', () {
    final meetings = WeeklyMeeting(
      startPeriod: 3,
      endPeriod: 4,
      startWeek: 2,
      endWeek: 14,
      pattern: WeekPattern.even,
      location: '教二-501',
    ).onWeekdays({4, 1});
    expect(meetings.map((m) => m.weekday), [1, 4]);
    expect(meetings.map((m) => m.id).toSet().length, 2);
    expect(
      meetings.every(
        (m) =>
            m.startPeriod == 3 &&
            m.endPeriod == 4 &&
            m.startWeek == 2 &&
            m.endWeek == 14 &&
            m.location == '教二-501',
      ),
      isTrue,
    );
    data.courses = [
      Course(name: '计算机网络', location: '默认教室', meetings: meetings),
    ];
    expect(data.occurrences(2).map((e) => e.weekday), [1, 4]);
    expect(data.occurrences(2).every((e) => e.location == '教二-501'), isTrue);
    expect(data.occurrences(1), isEmpty);
    expect(data.occurrences(3), isEmpty);
    expect(data.occurrences(15), isEmpty);
    expect(WeeklyMeeting().onWeekdays({}), isEmpty);
  });
  test('指定单周周日实验独立于常规双周课，地点教师继承或覆盖', () {
    data.courses = [
      Course(
        name: '网络',
        teacher: '任课教师',
        location: '教三-402',
        meetings: [
          WeeklyMeeting(
            weekday: 4,
            startPeriod: 3,
            endPeriod: 5,
            pattern: WeekPattern.even,
          ),
        ],
        extras: [
          ExtraMeeting(
            title: '大型实验',
            week: 9,
            weekday: 7,
            allDay: true,
            location: '实验楼-301',
            teacher: '实验教师',
            notes: '携带电脑',
          ),
        ],
      ),
    ];
    final extra = data.occurrences(9).single;
    expect(extra.allDay, isTrue);
    expect(extra.startMinute, 0);
    expect(extra.endMinute, 1440);
    expect(extra.teacher, '实验教师');
    expect(extra.location, '实验楼-301');
    expect(extra.notes, '携带电脑');
    expect(data.occurrences(2).single.location, '教三-402');
    data.courses.first.extras.first
      ..location = ''
      ..teacher = '';
    expect(data.occurrences(9).single.teacher, '任课教师');
    expect(data.occurrences(9).single.location, '教三-402');
  });
  test('冲突考虑单双周、周区间、同课内部、全天与课间', () {
    final network = Course(
      name: '网络',
      meetings: [
        WeeklyMeeting(
          weekday: 4,
          startPeriod: 3,
          endPeriod: 5,
          startWeek: 2,
          endWeek: 16,
          pattern: WeekPattern.even,
        ),
      ],
      extras: [ExtraMeeting(week: 9, weekday: 7, allDay: true)],
    );
    data.courses = [network];
    final other = Course(
      name: '另课',
      meetings: [
        WeeklyMeeting(
          weekday: 4,
          startPeriod: 4,
          endPeriod: 5,
          endWeek: 16,
          pattern: WeekPattern.odd,
        ),
      ],
    );
    expect(data.conflicts(other), isEmpty);
    other.meetings.single.pattern = WeekPattern.even;
    expect(data.conflicts(other), isNotEmpty);
    other.meetings.single
      ..startWeek = 18
      ..endWeek = 20;
    expect(data.conflicts(other), isEmpty);
    final extra = Course(
      name: '补课',
      extras: [
        ExtraMeeting(week: 9, weekday: 7, startMinute: 840, endMinute: 900),
      ],
    );
    expect(data.conflicts(extra), isNotEmpty);
    extra.extras.single.weekday = 6;
    expect(data.conflicts(extra), isEmpty);
    expect(
      data.conflicts(
        Course(
          name: '课间安排',
          extras: [
            ExtraMeeting(week: 2, weekday: 4, startMinute: 635, endMinute: 640),
          ],
        ),
      ),
      isEmpty,
    );
    final self = network.copy()
      ..meetings.add(network.meetings.single.copy()..id = newId());
    expect(data.conflicts(self), isNotEmpty);
  });
  test('连续时段端点相接不冲突，一秒前下课倒计时与铃后休息', () {
    final course = Course(
      name: '连堂',
      meetings: [WeeklyMeeting(weekday: 1, startPeriod: 3, endPeriod: 5)],
    );
    data.courses = [course];
    final event = data.occurrences(1).single;
    expect(
      event.secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 9, 50)),
      2700,
    );
    expect(
      event.secondsUntilLessonEnds(
        SchoolClock.instant(2026, 9, 21, 10, 34, 59),
      ),
      1,
    );
    expect(
      event.secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 10, 35)),
      isNull,
    );
    expect(event.status(SchoolClock.instant(2026, 9, 21, 10, 35)), '课间休息');
    expect(
      event.secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 10, 40)),
      2700,
    );
    expect(
      event.secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 12, 15)),
      isNull,
    );
    expect(
      event.secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 9, 49)),
      isNull,
    );
    final timed = Course(
      name: '连续实验',
      extras: [
        ExtraMeeting(weekday: 1, startMinute: 540, endMinute: 600),
        ExtraMeeting(weekday: 1, startMinute: 600, endMinute: 660),
      ],
    );
    data.courses = [];
    expect(data.conflicts(timed), isEmpty);
    data.courses = [timed];
    expect(
      data
          .occurrences(1)
          .first
          .secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 9, 30)),
      1800,
    );
    timed.extras.last.startMinute = 599;
    expect(data.conflicts(timed), isNotEmpty);
    timed.extras.first.allDay = true;
    expect(
      data
          .occurrences(1)
          .first
          .secondsUntilLessonEnds(SchoolClock.instant(2026, 9, 21, 9, 30)),
      isNull,
    );
  });
  for (final color in CourseColor.values) {
    test('颜色 JSON 往返 ${color.name}', () {
      data.courses = [
        Course(name: '颜色测试', color: color, meetings: [WeeklyMeeting()]),
      ];
      final restored = ScheduleCodec.decode(ScheduleCodec.encode(data));
      expect(restored.toJson(), data.toJson());
    });
  }
  test('拒绝损坏、超大、未知版本、不完整、非法 UUID 和日期的备份', () {
    expect(
      () => ScheduleCodec.decode(utf8.encode('not json')),
      throwsFormatException,
    );
    expect(
      () => ScheduleCodec.decode(List.filled(2000001, 0)),
      throwsFormatException,
    );
    final j = data.toJson();
    j['version'] = 99;
    expect(
      () => ScheduleCodec.decode(utf8.encode(jsonEncode(j))),
      throwsFormatException,
    );
    j['version'] = 1;
    (j['semester'] as Json)['startDate'] = '2026-02-30T00:00:00Z';
    expect(
      () => ScheduleCodec.decode(utf8.encode(jsonEncode(j))),
      throwsFormatException,
    );
    (j['semester'] as Json)['startDate'] = '2026-09-20T16:00:00Z';
    j.remove('courses');
    expect(
      () => ScheduleCodec.decode(utf8.encode(jsonEncode(j))),
      throwsFormatException,
    );
    final c = Course(name: '测试', meetings: [WeeklyMeeting()]).toJson()
      ..['id'] = 'not-uuid';
    final valid = data.toJson()..['courses'] = [c];
    expect(
      () => ScheduleCodec.decode(utf8.encode(jsonEncode(valid))),
      throwsFormatException,
    );
  });
  test('拒绝重复标识、无上课周、越界时间与缩短学期导致遗漏', () {
    data.courses = [
      Course(
        name: '测试',
        meetings: [
          WeeklyMeeting(startWeek: 3, endWeek: 3, pattern: WeekPattern.even),
        ],
      ),
    ];
    expect(data.validationError(), isNotNull);
    final c = data.courses.first;
    c.meetings.single.pattern = WeekPattern.odd;
    expect(data.validationError(), isNull);
    c.extras.add(ExtraMeeting(id: c.meetings.single.id));
    expect(data.validationError(), isNotNull);
    c.extras.single.id = newId();
    c.extras.single.week = 9;
    data.semester.weekCount = 8;
    expect(data.validationError(), isNotNull);
    data.semester.weekCount = 20;
    c.meetings.single.endPeriod = 99;
    expect(data.validationError(), isNotNull);
    c.meetings.single.endPeriod = 2;
    c.extras.single
      ..startMinute = 900
      ..endMinute = 800;
    expect(data.validationError(), isNotNull);
    c.extras.clear();
    data.courses.add(c.copy());
    expect(data.validationError(), isNotNull);
    data.courses.removeLast();
    data.semester.periods[1].startMinute = 480;
    expect(data.validationError(), isNotNull);
  });
  test('时间轴节次、休息、额外时段及整周适配', () {
    final base = TimelineLayout(data.semester.periods);
    expect(base.segments.length, 25);
    expect(base.position(480), 0);
    expect(base.position(525), 68);
    expect(base.position(530), 90);
    expect(base.position(1285), base.height);
    for (final h in [280.0, 640.0, 1000.0]) {
      final layout = TimelineLayout(data.semester.periods, fittingHeight: h);
      expect(layout.height, closeTo(h, 0.001));
      expect(layout.position(1285), closeTo(h, 0.001));
    }
    data.courses = [
      Course(
        name: '早晚实验',
        extras: [
          ExtraMeeting(startMinute: 360, endMinute: 420),
          ExtraMeeting(startMinute: 1300, endMinute: 1400),
        ],
      ),
    ];
    final layout = TimelineLayout(
      data.semester.periods,
      occurrences: data.occurrences(1),
    );
    expect(layout.position(360), 0);
    expect(layout.position(1400), layout.height);
  });
  test('课表折叠所有空休息，三节课对应三个等高节次且时刻映射连续', () {
    final layout = TimelineLayout(
      data.semester.periods,
      collapseBreaks: true,
      compact: true,
      fittingHeight: 520,
    );
    expect(layout.height, 520);
    expect(layout.segments.where((s) => s.height > 0).length, 13);
    expect(layout.position(525), layout.position(530));
    expect(layout.position(735), layout.position(840));
    expect(layout.position(590), 80);
    expect(layout.position(735) - layout.position(590), 120);
    for (var minute = 480; minute < 1285; minute++) {
      expect(
        layout.position(minute),
        lessThanOrEqualTo(layout.position(minute + 1)),
      );
    }
  });
  test('折叠休息仍保留午间及早晚额外实验，不会把常规连堂误当休息课', () {
    data.courses = [
      Course(
        name: '数据库原理',
        meetings: [WeeklyMeeting(startPeriod: 3, endPeriod: 5)],
      ),
      Course(
        name: '特别实验',
        extras: [
          ExtraMeeting(startMinute: 360, endMinute: 420),
          ExtraMeeting(startMinute: 780, endMinute: 810),
          ExtraMeeting(startMinute: 1300, endMinute: 1400),
        ],
      ),
    ];
    final events = data.occurrences(1);
    final layout = TimelineLayout(
      data.semester.periods,
      occurrences: events,
      collapseBreaks: true,
    );
    expect(
      layout.segments.where((s) => s.period == null && s.height > 0).length,
      3,
    );
    for (final event in events.where((e) => e.isExtra)) {
      expect(
        layout.position(event.endMinute) - layout.position(event.startMinute),
        68,
      );
    }
    expect(layout.position(735), layout.position(780));
    expect(layout.position(810), layout.position(840));
    final database = events.firstWhere((e) => !e.isExtra);
    expect(database.busyRanges.length, 3);
    expect(database.busyRanges.any((r) => r.contains(636)), isFalse);
    expect(layout.position(1400), layout.height);
  });
  test('重叠安排并排显示，首尾相接独占整列', () {
    final c = Course(
      name: '补课',
      extras: [
        ExtraMeeting(startMinute: 540, endMinute: 600),
        ExtraMeeting(startMinute: 599, endMinute: 660),
      ],
    );
    data.courses = [c];
    var lanes = OccurrenceLane.arrange(data.occurrences(1));
    expect(lanes.every((e) => e.count == 2), isTrue);
    expect(lanes.map((e) => e.index).toSet(), {0, 1});
    c.extras.last.startMinute = 600;
    lanes = OccurrenceLane.arrange(data.occurrences(1));
    expect(lanes.every((e) => e.count == 1), isTrue);
  });
  test('真正由 Swift 编码的备份，与 Swift 20 周课表计算逐字段一致', () {
    final imported = ScheduleCodec.decode(
      File('test/fixtures/ios-v1.json').readAsBytesSync(),
    );
    imported.semester.useSchoolCalendar = false;
    final golden =
        jsonDecode(
              File('test/fixtures/ios-occurrences.json').readAsStringSync(),
            )
            as List;
    final events = [for (var w = 1; w <= 20; w++) ...imported.occurrences(w)];
    final actual = events
        .map(
          (e) => {
            'id': e.id,
            'courseID': e.courseId,
            'sourceID': e.sourceId,
            'name': e.name,
            'teacher': e.teacher,
            'location': e.location,
            'color': e.color.name,
            'week': e.week,
            'weekday': e.weekday,
            'startMinute': e.startMinute,
            'endMinute': e.endMinute,
            'periodLabel': e.periodLabel,
            'timeLabel': e.timeLabel,
            'isExtra': e.isExtra,
            'allDay': e.allDay,
            'notes': e.notes,
            'busyRanges': e.busyRanges
                .map((r) => {'start': r.start, 'end': r.end})
                .toList(),
          },
        )
        .toList();
    expect(actual, golden);
    expect(
      ScheduleCodec.decode(ScheduleCodec.encode(imported)).toJson(),
      imported.toJson(),
    );
    expect(imported.courses.first.extras.first.allDay, isTrue);
  });
}
