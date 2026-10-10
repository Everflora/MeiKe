import unittest
from analyze_school_catalog import analyze


def row(identifier, teacher='示例教师', classes='班级甲', weeks='1-8周', start='3', code='DEMO101'):
    return {'JXBID': identifier, 'KCH': code, 'KCM': '演示课程', 'SKBJ': classes,
            'SKJS': teacher, 'SKXQ': '4', 'KSJC': start, 'JSJC': '5',
            'ZCMC': weeks, 'JASMC': '演示教室'}


def payload(rows, term='2026-2027-2'):
    return {'termCode': term, 'termName': '演示学期', 'rows': rows}


class CatalogTests(unittest.TestCase):
    def test_same_name_teacher_classes_merges_different_ids_and_phases(self):
        rooms, report = analyze(payload([row('A'), row('B', weeks='9-16周', start='4')]))
        self.assertEqual(len(rooms), 1)
        self.assertEqual(rooms[0]['sourceIdentities'], [['JXBID', 'A'], ['JXBID', 'B']])
        self.assertEqual(len(rooms[0]['arrangements']), 2)
        self.assertEqual(report['roomsMergedByRule'], 1)

    def test_different_teacher_or_classes_or_name_stays_separate(self):
        rooms, _ = analyze(payload([row('A'), row('B', teacher='另一教师'),
                                    row('C', classes='班级乙'), dict(row('D'), KCM='另一门课程')]))
        self.assertEqual(len(rooms), 4)

    def test_order_punctuation_and_spaces_do_not_change_membership(self):
        rooms, _ = analyze(payload([row('A', teacher='甲,乙', classes='班一、班二'),
                                    row('B', teacher=' 乙，甲 ', classes='班二; 班一')]))
        self.assertEqual(len(rooms), 1)

    def test_course_codes_and_meeting_times_do_not_override_rule(self):
        rooms, _ = analyze(payload([row('A'), row('B', code='OTHER', start='8')]))
        self.assertEqual(len(rooms), 1)
        self.assertEqual(rooms[0]['courseCodes'], ['DEMO101', 'OTHER'])

    def test_missing_class_or_teacher_does_not_merge_unknowns(self):
        rooms, report = analyze(payload([row('A', classes=''), row('B', classes=''),
                                        row('C', teacher=''), row('D', teacher='')]))
        self.assertEqual(len(rooms), 4)
        self.assertEqual(report['incompleteMatchingRows'], 4)

    def test_key_stable_when_ids_times_change_but_separates_terms(self):
        first, _ = analyze(payload([row('A')]))
        second, _ = analyze(payload([row('B', start='6')]))
        next_term, _ = analyze(payload([row('B')], term='2027-2028-2'))
        self.assertEqual(first[0]['roomKey'], second[0]['roomKey'])
        self.assertNotEqual(first[0]['roomKey'], next_term[0]['roomKey'])

    def test_metadata_and_schedule_preserved(self):
        course = dict(row('A'), BJDM='ADMIN-A', BJXX={'班级': '班级甲'}, JXBMC='演示教学班',
                      KXH='01', YPSJDD='1-8周 星期四 3-5节 教室甲,9-16周 星期四 4-5节 教室甲')
        rooms, report = analyze(payload([course]))
        self.assertEqual(rooms[0]['classDetails'], [{'班级': '班级甲'}])
        self.assertEqual(rooms[0]['administrativeClassCodes'], ['ADMIN-A'])
        self.assertEqual(rooms[0]['teachingClassNames'], ['演示教学班'])
        self.assertEqual(rooms[0]['arrangements'][0]['YPSJDD'], course['YPSJDD'])
        self.assertEqual(report['classesWithMultipleScheduleSegments'], 1)

    def test_source_id_with_conflicting_fields_is_flagged(self):
        rooms, report = analyze(payload([row('A'), row('A', classes='班级乙')]))
        self.assertEqual(len(rooms), 2)
        self.assertEqual(len(report['ambiguousSourceIdentities']), 1)

    def test_missing_id_can_group_with_complete_matching_fields(self):
        rooms, _ = analyze(payload([row(''), row('')]))
        self.assertEqual(len(rooms), 1)

    def test_incomplete_fields_without_id_require_review(self):
        rooms, report = analyze(payload([row('', classes='')]))
        self.assertEqual(rooms, [])
        self.assertEqual(len(report['unresolvedRows']), 1)

    def test_wrong_term_rejected(self):
        with self.assertRaises(ValueError):
            analyze(payload([dict(row('A'), XNXQDM='2025-2026-2')]))


if __name__ == '__main__':
    unittest.main()
