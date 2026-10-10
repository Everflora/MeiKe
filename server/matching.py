"""Match personal course names, teachers and weekly times to existing rooms."""
import re
import unicodedata


def normalize(value):
    return ' '.join(unicodedata.normalize('NFKC', value).split())


def teachers(value):
    return tuple(sorted({normalize(p) for p in re.split(r'[,，、;；\n]+', value) if normalize(p)}))


WEEK = r'\d+(?:-\d+)?周(?:\([单双]\))?'
CLAUSE = re.compile(r'(?P<weeks>' + WEEK + r'(?:\s*[,、]\s*' + WEEK + r')*)\s*星期'
                    r'(?P<day>[一二三四五六日天])\s*(?P<start>\d+)(?:-(?P<end>\d+))?节')


def schedule_times(value):
    result = set()
    value = unicodedata.normalize('NFKC', value or '').replace('–', '-').replace('—', '-')
    days = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7}
    for clause in CLAUSE.finditer(value):
        start, end = int(clause['start']), int(clause['end'] or clause['start'])
        if not 1 <= start <= end <= 30:
            continue
        for item in re.split(r'[,、]', clause['weeks']):
            week = re.fullmatch(r'\s*(\d+)(?:-(\d+))?周(?:\(([单双])\))?\s*', item)
            if not week:
                continue
            first, last = int(week[1]), int(week[2] or week[1])
            if not 1 <= first <= last <= 52:
                continue
            for number in range(first, last + 1):
                if week[3] == '单' and number % 2 == 0 or week[3] == '双' and number % 2 == 1:
                    continue
                result.add((number, days[clause['day']], start, end))
    return result


def requested_times(meetings):
    if not isinstance(meetings, list) or not 1 <= len(meetings) <= 100:
        raise ValueError('请为课程添加每周上课时间。')
    result = set()
    for meeting in meetings:
        if not isinstance(meeting, dict):
            raise ValueError('课程时间无效。')
        day, start, end = (meeting.get(k) for k in ('weekday', 'startPeriod', 'endPeriod'))
        weeks = meeting.get('weeks')
        if (any(type(v) is not int for v in (day, start, end)) or not 1 <= day <= 7
                or not 1 <= start <= end <= 30 or not isinstance(weeks, list)
                or not 1 <= len(weeks) <= 52
                or any(type(w) is not int or not 1 <= w <= 52 for w in weeks)):
            raise ValueError('课程周次、星期或节次无效。')
        result.update((w, day, start, end) for w in weeks)
    return result


def match_records(name, teacher, meetings, records):
    name, teacher = normalize(name), teachers(teacher)
    if not name or not teacher:
        raise ValueError('请补全课程名称和教师。')
    requested = requested_times(meetings)
    times = {}
    for room_id, row in records:
        if normalize(row.get('KCM') or '') != name or teachers(row.get('SKJS') or '') != teacher:
            continue
        times.setdefault(room_id, set()).update(schedule_times(row.get('YPSJDD')))
    return [room_id for room_id, slots in times.items() if requested <= slots]
