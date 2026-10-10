"""Group rooms by course name, teachers and attending classes."""
import argparse
import collections
import csv
import hashlib
import json
import re
import unicodedata
from pathlib import Path


def text(row, *keys):
    for key in keys:
        value = row.get(key)
        if value is not None and str(value).strip() not in ('', 'null'):
            return str(value).strip()
    return ''


def normalized(value):
    return ' '.join(unicodedata.normalize('NFKC', value).split())


def members(value):
    return tuple(sorted({normalized(p) for p in re.split(r'[,，、;；\n]+', value) if normalized(p)}))


def source_identity(row):
    if text(row, 'JXBID'):
        return ('JXBID', text(row, 'JXBID'))
    if text(row, 'KCH', 'KCDM') and text(row, 'JXBH'):
        return ('JXBH', text(row, 'KCH', 'KCDM'), text(row, 'JXBH'))
    return None


def matching_fields(row):
    return (normalized(text(row, 'KCM', 'KCMC')),
            members(text(row, 'SKJS', 'JSXM', 'JSM')), members(text(row, 'SKBJ')))


def identity(term, row):
    name, teachers, classes = matching_fields(row)
    if name and teachers and classes:
        return ('COURSE_TEACHER_CLASS', name, teachers, classes)
    return source_identity(row)


def room_key(term, identifier):
    return hashlib.sha256(json.dumps([term, *identifier], ensure_ascii=False,
                                    separators=(',', ':')).encode()).hexdigest()


def analyze(payload):
    term = str(payload.get('termCode', '')).strip()
    rows = payload.get('rows')
    if not term or not isinstance(rows, list) or not rows:
        raise ValueError('必须提供有效学期和非空课表数据。')
    grouped = collections.defaultdict(list)
    unresolved, fallback = [], []
    fields, coverage = collections.Counter(), collections.Counter()
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError('课表行必须是对象。')
        if text(row, 'XNXQDM') and text(row, 'XNXQDM') != term:
            raise ValueError('数据包含其他学期。')
        fields.update(row.keys())
        coverage.update(k for k, v in row.items() if v is not None and str(v).strip())
        missing = [k for k, v in zip(('课程名', '老师', '上课班级'), matching_fields(row)) if not v]
        key = identity(term, row)
        if key:
            grouped[key].append(row)
            if missing:
                fallback.append({'rowIndex': index, 'identity': list(key), 'missingFields': missing})
        else:
            unresolved.append({'rowIndex': index, 'missingFields': missing})
    catalog = []
    source_rooms = collections.defaultdict(list)
    for identifier, arrangements in grouped.items():
        codes = sorted({text(r, 'KCH', 'KCDM') for r in arrangements} - {''})
        names = sorted({text(r, 'KCM', 'KCMC') for r in arrangements} - {''})
        teachers = sorted({t for r in arrangements for t in members(text(r, 'SKJS', 'JSXM', 'JSM'))})
        classes = sorted({c for r in arrangements for c in members(text(r, 'SKBJ'))})
        sources = sorted({source_identity(r) for r in arrangements if source_identity(r)})
        slots, seen = [], set()
        for row in arrangements:
            slot = {k: text(row, k) for k in ('SKXQ', 'KSJC', 'JSJC', 'ZCMC', 'SKZC', 'JASMC', 'YPSJDD')}
            signature = json.dumps(slot, sort_keys=True)
            if signature not in seen:
                seen.add(signature)
                slots.append(slot)
        details = {json.dumps(r['BJXX'], ensure_ascii=False, sort_keys=True): r['BJXX']
                   for r in arrangements if r.get('BJXX')}
        numbers = sorted({text(r, 'JXBH', 'KXH') for r in arrangements} - {''})
        item = {'roomKey': room_key(term, identifier), 'termCode': term,
                'termName': str(payload.get('termName', term)), 'identity': list(identifier),
                'sourceIdentities': [list(s) for s in sources],
                'matchingRule': 'course-name-teacher-attending-class-v1'
                    if identifier[0] == 'COURSE_TEACHER_CLASS' else 'missing-fields-id-fallback',
                'courseCode': codes[0] if codes else '', 'courseCodes': codes,
                'name': ' / '.join(names), 'teachers': teachers,
                'classNumber': ' / '.join(numbers), 'classNumbers': numbers,
                'teachingClassNames': sorted({text(r, 'JXBMC') for r in arrangements} - {''}),
                'attendingClassNames': classes,
                'attendingClassValues': sorted({text(r, 'SKBJ') for r in arrangements} - {''}),
                'administrativeClassCodes': sorted({text(r, 'BJDM') for r in arrangements} - {''}),
                'classDetails': list(details.values()), 'arrangements': slots, 'rowCount': len(arrangements)}
        catalog.append(item)
        for source in sources:
            source_rooms[source].append(item['roomKey'])
    report = {'termCode': term, 'rows': len(rows), 'rooms': len(catalog),
              'completeMatchingRows': len(rows) - len(fallback) - len(unresolved),
              'incompleteMatchingRows': len(fallback) + len(unresolved),
              'fallbackRows': fallback, 'unresolvedRows': unresolved,
              'roomsMergedByRule': sum(r['matchingRule'].startswith('course-name') and
                                      len(r['sourceIdentities']) > 1 for r in catalog),
              'roomsWithMultipleTeachingClassIds': sum(len(r['sourceIdentities']) > 1 for r in catalog),
              'classesWithMultipleArrangements': sum(len(r['arrangements']) > 1 for r in catalog),
              'classesWithMultipleScheduleSegments': sum(
                  any(len(re.findall(r'星期[一二三四五六日天]', s['YPSJDD'])) > 1
                      for s in r['arrangements']) for r in catalog),
              'ambiguousSourceIdentities': [{'identity': list(s), 'roomKeys': keys}
                                            for s, keys in source_rooms.items() if len(keys) > 1],
              'fieldCounts': dict(fields), 'nonEmptyFieldCounts': dict(coverage),
              'rule': '同学期内课程名、老师集合、上课班级集合相同即同一讨论室；教学班ID、课程号、时间和周次不阻止合并。',
              'missingFieldPolicy': '任一匹配字段缺失时暂按原教学班标识保留，不将空值当作相同班级。'}
    return catalog, report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input')
    parser.add_argument('--output', default='.local/school-analysis')
    args = parser.parse_args()
    payload = json.loads(Path(args.input).read_text(encoding='utf-8'))
    catalog, report = analyze(payload)
    folder = Path(args.output)
    folder.mkdir(parents=True, exist_ok=True)
    ambiguous = {tuple(r['identity']) for r in report['ambiguousSourceIdentities']}
    mapping = [{'termCode': r['termCode'], 'identity': s, 'roomKey': r['roomKey']}
               for r in catalog for s in r['sourceIdentities'] if tuple(s) not in ambiguous]
    for name, value in [('catalog.json', catalog), ('report.json', report), ('class-room-mapping.json', mapping)]:
        (folder / name).write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    def csv_text(value):
        value = str(value)
        return "'" + value if value.lstrip().startswith(('=', '+', '-', '@')) else value
    with (folder / 'discussion-rooms.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream)
        writer.writerow(['学期', '课程号', '课程名称', '教师', '原教学班标识', '课序号',
                         '教学班名称', '上课班级', '班级代码', '班级明细', '排课信息',
                         '原始行数', '分组依据', '讨论室标识'])
        for r in catalog:
            writer.writerow(map(csv_text, [r['termName'], ' / '.join(r['courseCodes']), r['name'],
                ' / '.join(r['teachers']), json.dumps(r['sourceIdentities'], ensure_ascii=False), r['classNumber'],
                ' / '.join(r['teachingClassNames']), ' / '.join(r['attendingClassNames']),
                ' / '.join(r['administrativeClassCodes']), json.dumps(r['classDetails'], ensure_ascii=False),
                ' | '.join(s['YPSJDD'] for s in r['arrangements']), r['rowCount'], r['matchingRule'], r['roomKey']]))
    print(json.dumps({k: report[k] for k in ('termCode', 'rows', 'rooms',
                    'completeMatchingRows', 'incompleteMatchingRows', 'roomsMergedByRule')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
