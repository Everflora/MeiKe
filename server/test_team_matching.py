import copy
import math
import unittest
from team_matching.engine import (CONFIG, validate_config, validate_answers, validate_requirements,
                                  match_team, aggregate_to_team, pair_dimensions)


def full(**changes):
    answers = {q['id']: ([q['options'][0]['id']] if q['multiple'] else q['options'][0]['id']) for q in CONFIG['questions']}
    answers.update(changes)
    return answers


def team(mode='LIGHT', **changes):
    return dict(collaborationMode=mode, requiredSkills=[], requiredRoles=[], **changes)


class MatchingTests(unittest.TestCase):
    def test_configuration_complete_symmetric_and_bounded(self):
        validate_config(CONFIG)
        for mutate in [lambda c: c['matrices']['q1']['Q1_A'].pop('Q1_B'),
                       lambda c: c['matrices']['q1']['Q1_A'].update(Q1_B=.0123),
                       lambda c: c['baseWeights']['LIGHT'].update(G=-1),
                       lambda c: c['matrices']['q5']['Q5_A'].update(Q5_A=float('nan')),
                       lambda c: c['communicationWeights']['DEEP'].update(q9=.01)]:
            config = copy.deepcopy(CONFIG)
            mutate(config)
            with self.assertRaises((ValueError, KeyError)):
                validate_config(config)

    def test_every_option_and_question_scope(self):
        for q in CONFIG['questions']:
            for option in q['options']:
                validate_answers({q['id']: [option['id']] if q['multiple'] else option['id']})
        validate_answers(full(), complete=True)
        for answers in [{'q11': 'X'}, {'q1': 'Q1_Z'}, {'q1': ['Q1_A']}, {'q3': []},
                        {'q3': ['Q3_A'] * 2}, {'q3': ['Q3_A', 'Q3_G']},
                        {'q3': ['Q3_A', 'Q3_B', 'Q3_C', 'Q3_D']},
                        {'q10': ['Q10_A', 'Q10_B', 'Q10_C']}, {'q3': 'Q3_A'}]:
            with self.assertRaises(ValueError):
                validate_answers(answers)
        with self.assertRaises(ValueError):
            validate_answers({'q1': 'Q1_A'}, scope='profile')
        with self.assertRaises(ValueError):
            validate_answers({'q1': 'Q1_A'}, scope='round', complete=True)

    def test_A_light_ignores_q7_and_q8(self):
        a, b = full(), full()
        initial = match_team(a, [b], team())
        changed = match_team(full(q7='Q7_D', q8='Q8_C'), [b], team())
        self.assertEqual(initial, changed)

    def test_B_deep_frequency_difference_reduces_C(self):
        b = full(q7='Q7_D')
        same = match_team(full(q7='Q7_D'), [b], team('DEEP'))
        different = match_team(full(q7='Q7_A'), [b], team('DEEP'))
        self.assertLess(different['dimensions']['C'], same['dimensions']['C'])
        self.assertLessEqual(different['score'], same['score'])

    def test_C_no_declared_requirements_is_structurally_inapplicable(self):
        a = full(q3=['Q3_G'])
        result = match_team(a, [full()], team())
        self.assertIsNone(result['dimensions']['K'])
        self.assertEqual(result['score'], match_team(full(), [full()], team())['score'])

    def test_D_skill_gaps_and_two_slots(self):
        needs = team()
        needs['requiredSkills'] = [{'tag': 'Q3_E', 'count': 1}, {'tag': 'Q3_F', 'count': 1}]
        for value, expected in [(['Q3_E'], .5), (['Q3_E', 'Q3_F'], 1), (['Q3_G'], 0)]:
            result = match_team(full(q3=value), [full()], needs)
            self.assertEqual(result['dimensions']['K'], expected)
        missing = full()
        missing.pop('q3')
        self.assertIsNone(match_team(missing, [full()], needs)['dimensions']['K'])
        needs['requiredSkills'] = [{'tag': 'Q3_E', 'count': 2}]
        self.assertEqual(match_team(full(q3=['Q3_E']), [full()], needs)['dimensions']['K'], .5)

    def test_E_exact_76_7_without_Q10(self):
        self.assertEqual(match_team(full(q5='Q5_A'), [full(q5='Q5_C')], team())['score'], 76.7)

    def test_F_aggregation_uses_weakest_member(self):
        self.assertAlmostEqual(aggregate_to_team([.95, .90, .20]), .5383333333333333)
        self.assertEqual(aggregate_to_team([None, 0]), 0)
        self.assertIsNone(aggregate_to_team([None]))

    def test_G_missing_is_not_empty_skills_and_confidence_has_partial_coverage(self):
        needs = team()
        needs['requiredSkills'] = [{'tag': 'Q3_E', 'count': 1}]
        a = full()
        a.pop('q3')
        missing = match_team(a, [full()], needs)
        empty = match_team(full(q3=['Q3_G']), [full()], needs)
        self.assertIsNone(missing['dimensions']['K'])
        self.assertEqual(empty['dimensions']['K'], 0)
        self.assertLess(missing['confidence'], empty['confidence'])
        self.assertEqual(match_team(a, [full()], team())['confidence'], 1)
        partial = match_team({'q1': 'Q1_A'}, [full()], team())
        self.assertLess(partial['confidence'], .65)
        self.assertFalse(partial['displayScore'])
        self.assertEqual(partial['reasons'], ['问卷信息不足，请补全后查看匹配'])

    def test_I_preference_boost_only_when_dimension_applicable(self):
        a, b = full(q5='Q5_C'), full()
        base = match_team(a, [b], team())
        for choice in ('Q10_A', 'Q10_E', 'Q10_B'):
            self.assertEqual(base['score'], match_team(dict(a, q10=[choice]), [b], team())['score'])
        boosted = match_team(dict(a, q10=['Q10_C']), [b], team())
        d = boosted['dimensions']
        expected = math.floor((.45*d['G'] + .25*d['T'] + .10*d['C']) / .80 * 1000 + .5) / 10
        self.assertEqual(boosted['score'], expected)
        self.assertEqual(base['confidence'], boosted['confidence'])

    def test_Q9_changes_never_affect_any_mode_or_reasons(self):
        for mode in CONFIG['baseWeights']:
            base = match_team(full(), [full()], team(mode))
            for option in next(q for q in CONFIG['questions'] if q['id'] == 'q9')['options']:
                self.assertEqual(base, match_team(full(q9=option['id']), [full()], team(mode)))
            missing = full()
            missing.pop('q9')
            self.assertEqual(base, match_team(missing, [full()], team(mode)))

    def test_scores_bounded_one_decimal_all_pairs(self):
        for mode in CONFIG['baseWeights']:
            for q in CONFIG['questions']:
                for left in q['options']:
                    for right in q['options']:
                        a = full(**{q['id']: [left['id']] if q['multiple'] else left['id']})
                        b = full(**{q['id']: [right['id']] if q['multiple'] else right['id']})
                        result = match_team(a, [b], team(mode))
                        self.assertTrue(0 <= result['score'] <= 100)
                        self.assertAlmostEqual(result['score'] * 10, round(result['score'] * 10))
                        self.assertTrue(all(v is None or 0 <= v <= 1 for v in result['dimensions'].values()))

    def test_empty_team_and_bad_requirements_rejected(self):
        with self.assertRaisesRegex(ValueError, 'TEAM_HAS_NO_MEMBERS'):
            match_team(full(), [], team())
        for requirements in [[{'tag': 'Q3_G', 'count': 1}], [{'tag': 'Q3_A', 'count': True}],
                             [{'tag': 'Q3_A', 'count': 1, 'weight': float('inf')}],
                             [{'tag': 'Q3_A', 'count': 1}, {'tag': 'Q3_A', 'count': 1}]]:
            with self.assertRaises(ValueError):
                validate_requirements(requirements, 'skill')
        needs = team()
        needs['requiredRoles'] = [{'tag': 'Q4_A', 'count': 1}]
        self.assertEqual(match_team(full(q4='Q4_E'), [full(q4='Q4_C')], needs)['dimensions']['K'], .75)

    def test_partial_K_missing_data_and_filled_requirements(self):
        needs = team()
        needs['requiredSkills'] = [{'tag': 'Q3_E', 'count': 1}]
        needs['requiredRoles'] = [{'tag': 'Q4_A', 'count': 1}]
        candidate = full(q4='Q4_A')
        candidate.pop('q3')
        result = match_team(candidate, [full(q4='Q4_C')], needs)
        self.assertEqual(result['dimensions']['K'], 1)
        self.assertEqual(result['confidence'], .825)
        filled = match_team(candidate, [full(q3=['Q3_E'], q4='Q4_A')], needs)
        self.assertIsNone(filled['dimensions']['K'])
        self.assertEqual(filled['confidence'], 1)
        without_q10 = full()
        without_q10.pop('q10')
        self.assertEqual(match_team(without_q10, [full()], team())['score'], match_team(full(), [full()], team())['score'])


if __name__ == '__main__':
    unittest.main()
