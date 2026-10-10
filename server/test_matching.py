import unittest
from matching import match_records, schedule_times


class MatchingTests(unittest.TestCase):
    def meeting(self, weeks, start=3, end=4, day=4):
        return [{'weeks': weeks, 'weekday': day, 'startPeriod': start, 'endPeriod': end}]

    def record(self, time, teacher='示例教师', name='示例网络'):
        return {'KCM': name, 'SKJS': teacher, 'YPSJDD': time}

    def test_phase_subset_and_other_class_stays_separate(self):
        records = [('A', self.record('1-12周 星期四 3-5节,13-14周 星期四 3-4节')),
                   ('B', self.record('13-14周 星期二 3-4节'))]
        self.assertEqual(match_records('示例网络', '示例教师', self.meeting([13, 14]), records), ['A'])

    def test_union_across_source_ids_in_one_room(self):
        records = [('A', self.record('1-8周 星期四 3-4节')),
                   ('A', self.record('9-16周 星期四 3-4节'))]
        self.assertEqual(match_records('示例网络', '示例教师', self.meeting(list(range(1, 17))), records), ['A'])

    def test_odd_even_and_discontinuous_weeks(self):
        slots = schedule_times('3-9周(单),12周 星期四 3-4节 教室甲,6-12周(双) 星期二 8-10节')
        self.assertIn((3, 4, 3, 4), slots)
        self.assertIn((12, 4, 3, 4), slots)
        self.assertNotIn((4, 4, 3, 4), slots)
        self.assertIn((10, 2, 8, 10), slots)

    def test_no_match_for_wrong_weeks_period_teacher(self):
        records = [('A', self.record('13-14周 星期四 3-4节'))]
        for weeks, start, teacher in [([12], 3, '示例教师'), ([13], 2, '示例教师'), ([13], 3, '另一教师')]:
            self.assertEqual(match_records('示例网络', teacher, self.meeting(weeks, start), records), [])

    def test_ambiguous_matches_are_returned_for_user_choice(self):
        records = [('A', self.record('13-14周 星期四 3-4节')),
                   ('B', self.record('13-14周 星期四 3-4节'))]
        self.assertEqual(match_records('示例网络', '示例教师', self.meeting([13]), records), ['A', 'B'])

    def test_invalid_or_missing_meetings_rejected(self):
        with self.assertRaises(ValueError):
            match_records('示例网络', '示例教师', [], [])
        with self.assertRaises(ValueError):
            match_records('示例网络', '示例教师', self.meeting([0]), [])


if __name__ == '__main__':
    unittest.main()
