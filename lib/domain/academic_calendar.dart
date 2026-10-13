/// Verified public SEU calendar. Dates are civil days (UTC midnight), not instants.
enum CalendarKind { information, holiday, makeup, suspension, exams, vacation }

class CalendarEvent {
  CalendarEvent(
    this.title,
    this.start,
    this.end,
    this.kind,
    this.details, {
    this.sourceDate,
  });
  final String title, details;
  final DateTime start, end;
  final CalendarKind kind;
  final DateTime? sourceDate;
  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
  bool get stopsClasses => const [
    CalendarKind.holiday,
    CalendarKind.suspension,
    CalendarKind.exams,
    CalendarKind.vacation,
  ].contains(kind);
  String get badge => switch (kind) {
    CalendarKind.makeup => '补课',
    CalendarKind.holiday => '放假',
    CalendarKind.suspension => '校运会',
    CalendarKind.exams => '考试',
    CalendarKind.vacation => title,
    CalendarKind.information => title.endsWith('学期上课') ? '开学' : title,
  };
  String get dateLabel =>
      start == end ? shortDate(start) : '${shortDate(start)}–${shortDate(end)}';
  static String shortDate(DateTime day) => '${day.month}.${day.day}';
}

class CalendarTerm {
  CalendarTerm(this.name, this.start, this.firstMonday, this.end, this.weeks);
  final String name;
  final DateTime start, firstMonday, end;
  final int weeks;
  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
}

abstract final class SeuCalendar {
  static const year = '2026—2027';
  static const source = 'https://jwc.seu.edu.cn/dndx2026w2027xnxl/list.htm';
  static const holidaySource =
      'https://jwc.seu.edu.cn/_upload/article/files/c3/32/c3b5a51f41ddab0e8f2e66069bf2/29abd5e8-e65f-492c-866e-0978dd0dc4f4.pdf';
  static DateTime _d(int y, int m, int d) => DateTime.utc(y, m, d);
  static final terms = [
    CalendarTerm('暑期学校', _d(2026, 8, 24), _d(2026, 8, 24), _d(2026, 9, 19), 4),
    CalendarTerm('秋季学期', _d(2026, 9, 20), _d(2026, 9, 21), _d(2027, 1, 24), 18),
    CalendarTerm('春季学期', _d(2027, 2, 22), _d(2027, 2, 22), _d(2027, 6, 27), 18),
  ];
  static final events = <CalendarEvent>[
    CalendarEvent(
      '教职工上班',
      _d(2026, 8, 20),
      _d(2026, 8, 20),
      CalendarKind.information,
      '教职工开始上班。',
    ),
    CalendarEvent(
      '暑期学校',
      _d(2026, 8, 24),
      _d(2026, 9, 19),
      CalendarKind.information,
      '本科生暑期学校；研究生教学由导师或课题组安排。',
    ),
    CalendarEvent(
      '在校生注册',
      _d(2026, 8, 24),
      _d(2026, 8, 28),
      CalendarKind.information,
      '秋季学期在校生注册。',
    ),
    CalendarEvent(
      '本科新生报到',
      _d(2026, 8, 29),
      _d(2026, 8, 29),
      CalendarKind.information,
      '本科新生报到注册。',
    ),
    CalendarEvent(
      '本科新生军训',
      _d(2026, 8, 30),
      _d(2026, 9, 19),
      CalendarKind.information,
      '本科新生军训。',
    ),
    CalendarEvent(
      '学位评定委员会会议',
      _d(2026, 9, 9),
      _d(2026, 9, 9),
      CalendarKind.information,
      '校学位评定委员会会议。',
    ),
    CalendarEvent(
      '研究生新生报到',
      _d(2026, 9, 15),
      _d(2026, 9, 15),
      CalendarKind.information,
      '研究生新生报到注册。',
    ),
    CalendarEvent(
      '新生开学典礼',
      _d(2026, 9, 17),
      _d(2026, 9, 17),
      CalendarKind.information,
      '新生开学典礼。',
    ),
    CalendarEvent(
      '秋季学期上课',
      _d(2026, 9, 20),
      _d(2026, 9, 20),
      CalendarKind.information,
      '秋季学期开始上课；第一教学周的周一为9月21日。',
    ),
    CalendarEvent(
      '国庆补课',
      _d(2026, 9, 20),
      _d(2026, 9, 20),
      CalendarKind.makeup,
      '补10月6日（周二，第3周）的课，按原日期的教学周和单双周排课。',
      sourceDate: _d(2026, 10, 6),
    ),
    CalendarEvent(
      '中秋节',
      _d(2026, 9, 25),
      _d(2026, 9, 27),
      CalendarKind.holiday,
      '放假，不调休；常规课程不显示。',
    ),
    CalendarEvent(
      '国庆节',
      _d(2026, 10, 1),
      _d(2026, 10, 7),
      CalendarKind.holiday,
      '放假；9月20日和10月10日分别补10月6日和10月7日的课。',
    ),
    CalendarEvent(
      '国庆补课',
      _d(2026, 10, 10),
      _d(2026, 10, 10),
      CalendarKind.makeup,
      '补10月7日（周三，第3周）的课，替代当天常规课程。',
      sourceDate: _d(2026, 10, 7),
    ),
    CalendarEvent(
      '校运会',
      _d(2026, 11, 5),
      _d(2026, 11, 7),
      CalendarKind.suspension,
      '停课不补；手动添加的额外安排保留并标注。',
    ),
    CalendarEvent(
      '学位评定委员会会议',
      _d(2026, 12, 16),
      _d(2026, 12, 16),
      CalendarKind.information,
      '校学位评定委员会会议。',
    ),
    CalendarEvent(
      '停课复习考试',
      _d(2027, 1, 11),
      _d(2027, 1, 24),
      CalendarKind.exams,
      '秋季学期停课复习考试；不显示常规课程，具体考试时间以个人安排为准。',
    ),
    CalendarEvent(
      '寒假',
      _d(2027, 1, 25),
      _d(2027, 2, 21),
      CalendarKind.vacation,
      '学生寒假；教职工轮休至2月18日。',
    ),
    CalendarEvent(
      '教职工上班',
      _d(2027, 2, 19),
      _d(2027, 2, 19),
      CalendarKind.information,
      '教职工开始上班。',
    ),
    CalendarEvent(
      '春季学期上课',
      _d(2027, 2, 22),
      _d(2027, 2, 22),
      CalendarKind.information,
      '春季学期开始上课，第一周周一为2月22日。',
    ),
    CalendarEvent(
      '在校生注册',
      _d(2027, 2, 22),
      _d(2027, 2, 26),
      CalendarKind.information,
      '春季学期在校生注册。',
    ),
    CalendarEvent(
      '春博报到',
      _d(2027, 3, 3),
      _d(2027, 3, 3),
      CalendarKind.information,
      '2027级春博报到，上课时间为3月8日。',
    ),
    CalendarEvent(
      '春博上课',
      _d(2027, 3, 8),
      _d(2027, 3, 8),
      CalendarKind.information,
      '2027级春博开始上课。',
    ),
    CalendarEvent(
      '学位评定委员会会议',
      _d(2027, 3, 17),
      _d(2027, 3, 17),
      CalendarKind.information,
      '校学位评定委员会会议。',
    ),
    CalendarEvent(
      '停课复习考试',
      _d(2027, 6, 14),
      _d(2027, 6, 27),
      CalendarKind.exams,
      '春季学期停课复习考试；不显示常规课程。',
    ),
    CalendarEvent(
      '学位评定委员会会议',
      _d(2027, 6, 18),
      _d(2027, 6, 18),
      CalendarKind.information,
      '校学位评定委员会会议。',
    ),
    CalendarEvent(
      '本科生毕业离校手续',
      _d(2027, 6, 19),
      _d(2027, 6, 25),
      CalendarKind.information,
      '本科生办理毕业离校手续；研究生在毕业之日起两周内，6月批次在6月25日前。',
    ),
    CalendarEvent(
      '毕业典礼',
      _d(2027, 6, 22),
      _d(2027, 6, 23),
      CalendarKind.information,
      '毕业典礼。',
    ),
    CalendarEvent(
      '暑假',
      _d(2027, 6, 28),
      _d(2027, 8, 15),
      CalendarKind.vacation,
      '学生暑假。',
    ),
    CalendarEvent(
      '教职工轮休',
      _d(2027, 7, 5),
      _d(2027, 8, 12),
      CalendarKind.information,
      '教职工轮休。',
    ),
    CalendarEvent(
      '教职工上班',
      _d(2027, 8, 13),
      _d(2027, 8, 13),
      CalendarKind.information,
      '教职工开始上班。',
    ),
  ];
  static List<CalendarEvent> on(DateTime day) =>
      events.where((e) => e.contains(day)).toList();
  static CalendarEvent? makeupOn(DateTime day) =>
      on(day).where((e) => e.kind == CalendarKind.makeup).firstOrNull;
  static CalendarEvent? stoppageOn(DateTime day) =>
      on(day).where((e) => e.stopsClasses).firstOrNull;
  static CalendarEvent? highlight(DateTime day) =>
      makeupOn(day) ??
      stoppageOn(day) ??
      on(day).where((e) => e.start == day).firstOrNull ??
      on(day).firstOrNull;
  static CalendarTerm? forMonday(DateTime day) =>
      terms.where((t) => t.firstMonday == day).firstOrNull;
}
