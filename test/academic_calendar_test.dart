import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/domain/academic_calendar.dart';
import 'package:seu_timetable/domain/schedule.dart';

void main() {
  ScheduleData autumn() => ScheduleData(
    semester: Semester(
      name: '大三上',
      startDate: SchoolClock.instant(2026, 9, 21),
      weekCount: 20,
    ),
  );
  List<Occurrence> on(ScheduleData data, int y, int m, int d) {
    final date = SchoolClock.instant(y, m, d);
    return data.occurrences(
      SchoolClock.week(date, data.semester),
      weekday: SchoolClock.weekday(date),
    );
  }

  Course lesson(
    String name,
    int day, {
    WeekPattern pattern = WeekPattern.every,
    int start = 1,
    int end = 20,
  }) => Course(
    name: name,
    teacher: '教师',
    location: '默认教室',
    meetings: [
      WeeklyMeeting(
        weekday: day,
        startWeek: start,
        endWeek: end,
        pattern: pattern,
        startPeriod: 3,
        endPeriod: 4,
        location: '教三-304',
      ),
    ],
  );

  test('中秋、国庆、校运会、考试与寒假只隐藏常规课，节后继续', () {
    final data = autumn()
      ..courses = [for (var day = 1; day <= 7; day++) lesson('课程$day', day)];
    for (final date in [
      [2026, 9, 25],
      [2026, 9, 27],
      [2026, 10, 1],
      [2026, 10, 6],
      [2026, 10, 7],
      [2026, 11, 5],
      [2026, 11, 6],
      [2026, 11, 7],
      [2027, 1, 11],
      [2027, 1, 24],
      [2027, 1, 25],
    ]) {
      expect(on(data, date[0], date[1], date[2]), isEmpty, reason: '$date');
    }
    expect(on(data, 2026, 9, 28).single.name, '课程1');
    expect(on(data, 2026, 11, 8).single.name, '课程7');
  });
  test('9月20日补第3周周二，使用原周次单双周而非第0周', () {
    final data = autumn()
      ..courses = [
        lesson('单周课程', 2, pattern: WeekPattern.odd, start: 3, end: 3),
        lesson('双周课程', 2, pattern: WeekPattern.even),
        lesson('周日课程', 7),
      ];
    final events = on(data, 2026, 9, 20);
    expect(data.firstDisplayWeek, 0);
    expect(data.weekLabel(0), '开学补课周');
    expect(events.map((e) => e.name), ['单周课程']);
    final e = events.single;
    expect(e.week, 0);
    expect(e.weekday, 7);
    expect(e.makeupFor, DateTime.utc(2026, 10, 6));
    expect(e.calendarNote, contains('第3周'));
    expect(e.location, '教三-304');
    expect(e.teacher, '教师');
    expect(e.startMinute, 590);
    expect(e.endMinute, 685);
    expect(e.sourceId, data.courses.first.meetings.first.id);
    expect(on(data, 2026, 10, 6), isEmpty);
  });
  test('10月10日只补10月7日的常规课，替代周六原课；额外安排不复制', () {
    final data = autumn()
      ..courses = [lesson('周三第3周', 3, start: 3, end: 3), lesson('周六课', 6)];
    data.courses.first.extras.add(
      ExtraMeeting(title: '明确日期实验', week: 3, weekday: 3),
    );
    final saturday = on(data, 2026, 10, 10);
    expect(saturday.map((e) => e.name), ['周三第3周']);
    expect(saturday.single.makeupFor, DateTime.utc(2026, 10, 7));
    final holiday = on(data, 2026, 10, 7);
    expect(holiday.single.isExtra, isTrue);
    expect(holiday.single.calendarNote, contains('停课日额外安排'));
  });
  test('全天与定时实验在停课日保留，原始课程、日期与备份不修改', () {
    final data = autumn()..courses = [lesson('实验课程', 4)];
    data.courses.first.extras.addAll([
      ExtraMeeting(week: 7, weekday: 4, allDay: true, location: '实301'),
      ExtraMeeting(week: 7, weekday: 5, startMinute: 800, endMinute: 900),
    ]);
    final before = jsonEncode(data.toJson());
    expect(on(data, 2026, 11, 5).single.allDay, isTrue);
    expect(on(data, 2026, 11, 5).single.location, '实301');
    expect(on(data, 2026, 11, 6).single.calendarNote, contains('校运会'));
    for (var week = 0; week <= 20; week++) {
      data.occurrences(week);
    }
    expect(jsonEncode(data.toJson()), before);
  });
  test('关闭联动恢复原始每周安排，偏好随备份保存，旧备份可读取', () {
    final data = autumn()..courses = [lesson('周二课', 2)];
    data.semester.useSchoolCalendar = false;
    expect(on(data, 2026, 10, 6).single.name, '周二课');
    final copy = ScheduleCodec.decode(ScheduleCodec.encode(data));
    expect(copy.semester.useSchoolCalendar, isFalse);
    expect(copy.calendarTerm, isNull);
    final legacy = data.toJson();
    (legacy['semester'] as Json).remove('useSchoolCalendar');
    final restored = ScheduleData.fromJson(legacy);
    expect(restored.calendarTerm?.name, '秋季学期');
    expect(on(restored, 2026, 10, 6), isEmpty);
  });
  test('未匹配校历的学期保持原课表，校历不会擅自移动开学日', () {
    final data = autumn();
    data.semester.startDate = SchoolClock.instant(2026, 9, 14);
    data.courses = [lesson('原始课程', 4)];
    expect(data.calendarTerm, isNull);
    expect(data.firstDisplayWeek, 1);
    expect(on(data, 2026, 10, 1).single.name, '原始课程');
    expect(data.semester.startDate, SchoolClock.instant(2026, 9, 14));
  });
  test('春季期末停课，暑假与非本学期不再延续常规课；2027假期不推测', () {
    final data = ScheduleData(
      semester: Semester(
        startDate: SchoolClock.instant(2027, 2, 22),
        weekCount: 30,
      ),
      courses: [lesson('课程', 1, end: 30)],
    );
    expect(on(data, 2027, 6, 7).single.name, '课程');
    expect(on(data, 2027, 6, 14), isEmpty);
    expect(on(data, 2027, 6, 28), isEmpty);
    expect(on(data, 2027, 8, 16), isEmpty);
    expect(SeuCalendar.stoppageOn(DateTime.utc(2027, 5, 1)), isNull);
  });
  test('课表冲突检查包含校历补课与手动实验的真实重叠', () {
    final data = autumn()
      ..courses = [
        Course(
          name: '实验',
          extras: [
            ExtraMeeting(week: 3, weekday: 6, startMinute: 600, endMinute: 650),
          ],
        ),
      ];
    expect(data.conflicts(lesson('补课', 3)), isNotEmpty);
  });
  test('跨时区同一上海日期执行同一停课与补课规则', () {
    final data = autumn()..courses = [lesson('周三', 3)];
    final instant = DateTime.parse('2026-10-09T16:30:00Z');
    final events = data.occurrences(
      SchoolClock.week(instant, data.semester),
      weekday: SchoolClock.weekday(instant),
    );
    expect(events.single.makeupFor, DateTime.utc(2026, 10, 7));
    expect(data.calendarEventOn(instant)?.kind, CalendarKind.makeup);
  });
  test('16周课程仍可查看校历17和18周考试，且不改写教学周数', () {
    final data = autumn();
    data.semester.weekCount = 16;
    expect(data.lastDisplayWeek, 18);
    expect(
      data.calendarEventOn(SchoolClock.date(17, 1, data.semester))?.kind,
      CalendarKind.exams,
    );
    expect(data.occurrences(17), isEmpty);
    expect(data.semester.weekCount, 16);
    data.semester.useSchoolCalendar = false;
    expect(data.lastDisplayWeek, 16);
  });
}
