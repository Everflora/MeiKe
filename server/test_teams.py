import json
import tempfile
import threading
import unittest
from pathlib import Path
from app import ApiError, Database
from team_matching import CONFIG
from test_team_matching import full


class TeamTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Database(Path(self.temp.name) / 'test.sqlite3')
        self.db.import_catalog([{'termCode': 'TEST', 'name': '仅测试', 'identity': ['JXBID', 'TEST']}])
        self.people = [self.db.route('POST', '/v1/sessions', {}, {'name': f'测试{i}'}, '') for i in range(4)]
        self.room = self.call('POST', '/v1/rooms/resolve', {'termCode': 'TEST', 'identity': ['JXBID', 'TEST']})['room']['roomKey']
        for i in range(4):
            self.call('POST', '/v1/team-consent', {'offeringId': self.room, 'consent': True, 'confirmMembership': True}, person=i)
            self.profile(i)
        self.rid = self.call('POST', '/v1/team-rounds', {'offeringId': self.room, 'name': '任务一'})['id']
        for i in range(4):
            self.preferences(i)

    def call(self, method, path, body=None, query=None, person=0):
        return self.db.route(method, path, query or {}, body or {}, self.people[person]['token'])

    def profile(self, person, **changes):
        answers = full(**changes)
        self.call('PUT', '/v1/team-profile', {'answers': {q['id']: answers[q['id']] for q in CONFIG['questions'] if q['scope'] == 'profile'}, 'questionnaireVersion': 1}, person=person)

    def preferences(self, person, rid=None, **changes):
        answers = full(**changes.pop('answers', {}))
        self.call('PUT', '/v1/team-preferences/' + (rid or self.rid), dict(answers={q['id']: answers[q['id']] for q in CONFIG['questions'] if q['scope'] == 'round'}, questionnaireVersion=1, **changes), person=person)

    def other_course(self):
        self.db.import_catalog([{'termCode': 'TEST', 'name': '另一门课', 'identity': ['JXBID', 'OTHER']}])
        room = self.call('POST', '/v1/rooms/resolve', {'termCode': 'TEST', 'identity': ['JXBID', 'OTHER']})['room']['roomKey']
        for i in range(4):
            self.call('POST', '/v1/team-consent', {'offeringId': room, 'consent': True, 'confirmMembership': True}, person=i)
        return self.call('POST', '/v1/team-default-round', {'offeringId': room})['round']['id']

    def create(self, person=0, **changes):
        body = dict(roundId=self.rid, name='测试团队', capacity=4, collaborationMode='LIGHT')
        body.update(changes)
        return self.call('POST', '/v1/team-list', body, person=person)['team']

    def apply(self, team, person, **body):
        return self.call('POST', f"/v1/team-detail/{team['id']}/apply", body, person=person)['id']

    def review(self, aid, action='accept', person=0):
        return self.call('POST', '/v1/team-applications/' + aid, {'action': action}, person=person)

    def assert_code(self, code, function):
        with self.assertRaises(ApiError) as caught:
            function()
        self.assertEqual(caught.exception.code, code)

    def test_simple_views_browse_without_questionnaire_and_show_only_my_membership(self):
        own = self.create()
        other = self.create(person=1, name='其他队伍')
        query = {'roundId': [self.rid], 'view': ['recruiting']}
        with self.db.connect() as db:
            db.execute('DELETE FROM team_profiles WHERE user_id=?', (self.people[2]['user']['id'],))
            db.execute('DELETE FROM team_preferences WHERE user_id=?', (self.people[2]['user']['id'],))
        result = self.call('GET', '/v1/team-list', query=query, person=2)['teams']
        self.assertEqual({t['id'] for t in result}, {own['id'], other['id']})
        self.assertTrue(all(not t['match']['displayScore'] for t in result))
        self.assertEqual([t['id'] for t in self.call('GET', '/v1/team-list', query=query)['teams']], [other['id']])
        mine = self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'view': ['mine']})['teams']
        self.assertEqual([t['id'] for t in mine], [own['id']])
        self.call('POST', f"/v1/team-detail/{other['id']}/close", person=1)
        self.assertEqual(self.call('GET', '/v1/team-list', query=query)['teams'], [])

    def test_my_view_preserves_legacy_round_membership_and_course_isolation(self):
        own = self.create()
        with self.db.connect() as db:
            db.execute('INSERT INTO group_rounds VALUES (?,?,?,?,0)', ('legacy-round', self.room, '旧活动', self.people[0]['user']['id']))
            db.execute('UPDATE teams SET round_id=? WHERE id=?', ('legacy-round', own['id']))
            db.execute('UPDATE team_members SET round_id=? WHERE team_id=?', ('legacy-round', own['id']))
        other_rid = self.other_course()
        self.preferences(0, rid=other_rid)
        other = self.create(roundId=other_rid, name='另一课程队伍')
        result = self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'view': ['mine']})['teams']
        self.assertEqual([t['id'] for t in result], [own['id']])
        self.assertNotIn(other['id'], [t['id'] for t in result])
        with self.db.connect() as db:
            db.execute('DELETE FROM team_consents WHERE user_id=? AND offering_id=?', (self.people[0]['user']['id'], self.room))
        self.assert_code('CONSENT_REQUIRED', lambda: self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'view': ['mine']}))

    def test_MVP_create_recommend_apply_review_leave_close_and_restart(self):
        team = self.create()
        result = self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']}, person=1)
        self.assertEqual(result['teams'][0]['match']['score'], 100)
        aid = self.apply(team, 1)
        self.assert_code('APPLICATION_PENDING', lambda: self.apply(team, 1))
        self.assert_code('LEADER_REQUIRED', lambda: self.review(aid, person=2))
        self.review(aid)
        self.assert_code('APPLICATION_RESOLVED', lambda: self.review(aid))
        self.assert_code('ALREADY_JOINED', lambda: self.apply(team, 1))
        self.db = Database(self.db.file)
        self.assertEqual(self.call('GET', '/v1/team-detail/' + team['id'])['team']['memberCount'], 2)
        self.call('POST', f"/v1/team-detail/{team['id']}/leave")
        self.assertTrue(self.call('GET', '/v1/team-detail/' + team['id'], person=1)['team']['manager'])
        self.call('POST', f"/v1/team-detail/{team['id']}/close", person=1)
        self.assert_code('TEAM_CLOSED', lambda: self.apply(team, 2))

    def test_H_concurrent_final_slot_only_one_accepts(self):
        team = self.create(capacity=2)
        pending = [self.apply(team, i) for i in (1, 2)]
        barrier = threading.Barrier(2)
        outcomes = []
        def approve(aid):
            barrier.wait()
            try:
                self.review(aid)
                outcomes.append('ACCEPTED')
            except ApiError as exc:
                outcomes.append(exc.code)
        threads = [threading.Thread(target=approve, args=(aid,)) for aid in pending]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(15)
            self.assertFalse(thread.is_alive())
        self.assertCountEqual(outcomes, ['ACCEPTED', 'TEAM_FULL'])
        actual = self.call('GET', '/v1/team-detail/' + team['id'])['team']
        self.assertEqual((actual['status'], actual['memberCount']), ('FULL', 2))
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']}, person=3)['teams'], [])

    def test_H_closed_joined_other_round_and_draft_not_recommended(self):
        team = self.create(publish=False)
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [self.rid]}, person=1)['teams'], [])
        self.assert_code('TEAM_NOT_FOUND', lambda: self.apply(team, 1))
        self.call('POST', f"/v1/team-detail/{team['id']}/publish")
        rid2 = self.other_course()
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [rid2], 'recommend': ['true']}, person=1)['teams'], [])
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']})['teams'], [])
        self.call('POST', f"/v1/team-detail/{team['id']}/close")
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']}, person=1)['teams'], [])

    def test_private_answers_spoofed_identity_and_consent(self):
        self.assert_code('INVALID_INPUT', lambda: self.call('PUT', '/v1/team-profile', {'answers': {}, 'userId': self.people[1]['user']['id']}))
        with self.assertRaises(ApiError) as error:
            self.db.route('GET', '/v1/team-profile', {}, {}, '')
        self.assertEqual(error.exception.status, 401)
        team = self.create()
        text = json.dumps(self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']}, person=1))
        self.assertNotIn('Q1_A', text)
        self.assertNotIn('answers', text)
        with self.db.connect() as db:
            db.execute('DELETE FROM team_consents WHERE user_id=?', (self.people[1]['user']['id'],))
        self.assert_code('CONSENT_REQUIRED', lambda: self.apply(team, 1))

    def test_round_answers_overrides_and_optional_tags_are_independent(self):
        rid2 = self.other_course()
        self.preferences(1, rid=rid2, answers={'q1': 'Q1_C'}, overrides={'q3': ['Q3_E']})
        first = self.call('GET', '/v1/team-preferences/' + self.rid, person=1)
        second = self.call('GET', '/v1/team-preferences/' + rid2, person=1)
        self.assertEqual(first['answers']['q1'], 'Q1_A')
        self.assertEqual(second['answers']['q1'], 'Q1_C')
        self.assertEqual(second['overrides']['q3'], ['Q3_E'])
        self.assertEqual(self.call('GET', '/v1/team-profile', person=1)['answers']['q3'], ['Q3_A'])
        team = self.create()
        query = {'roundId': [self.rid], 'recommend': ['true']}
        before = self.call('GET', '/v1/team-list', query=query, person=1)['teams'][0]['match']
        profile = self.call('GET', '/v1/team-profile', person=1)
        self.call('PUT', '/v1/team-profile', {'answers': profile['answers'], 'tags': {'mbti': 'INTJ', 'zodiac': '白羊座'}, 'questionnaireVersion': 1}, person=1)
        self.assertEqual(before, self.call('GET', '/v1/team-list', query=query, person=1)['teams'][0]['match'])
        self.profile(1, q5='Q5_C')
        self.assertNotEqual(before, self.call('GET', '/v1/team-list', query=query, person=1)['teams'][0]['match'])

    def test_offline_requires_active_confirmation_not_Q8(self):
        self.preferences(0, canMeetOffline=True)
        team = self.create(mustMeetOffline=True)
        self.assert_code('OFFLINE_CONFIRMATION_REQUIRED', lambda: self.apply(team, 1))
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']}, person=1)['teams'], [])
        self.preferences(1, canMeetOffline=True)
        self.assert_code('OFFLINE_CONFIRMATION_REQUIRED', lambda: self.apply(team, 1))
        self.review(self.apply(team, 1, offlineConfirmed=True))

    def test_private_avoidance_bidirectional_removal_and_cancellation(self):
        team = self.create()
        aid = self.apply(team, 1)
        self.review(aid, action='cancel', person=1)
        self.review(self.apply(team, 1))
        self.call('POST', f"/v1/team-detail/{team['id']}/remove", {'userId': self.people[1]['user']['id']})
        self.assert_code('TEAM_UNAVAILABLE', lambda: self.apply(team, 1))
        self.call('POST', '/v1/team-avoidances', {'userId': self.people[2]['user']['id']})
        self.assert_code('TEAM_UNAVAILABLE', lambda: self.apply(team, 2))
        self.assertEqual(self.call('GET', '/v1/team-avoidances', person=2)['users'], [])
        self.assertEqual(self.call('GET', '/v1/team-list', query={'roundId': [self.rid], 'recommend': ['true']}, person=2)['teams'], [])
        self.call('DELETE', '/v1/team-avoidances', {'userId': self.people[2]['user']['id']})
        self.apply(team, 2)

    def test_common_time_explicit_consent_no_raw_schedule_or_other_answers(self):
        team = self.create(needsMeeting=True)
        path = f"/v1/team-detail/{team['id']}/meeting-times"
        self.assertEqual(self.call('GET', path, person=1)['slots'], [])
        for person, slots in [(0, [10, 11, 12]), (1, [11, 12, 13])]:
            self.call('PUT', '/v1/team-availability/' + self.rid, {'consent': True, 'week': '2026-10-12', 'slots': slots}, person=person)
        self.assertEqual(self.call('GET', path, person=1)['slots'], [11, 12])
        self.assertEqual(self.call('GET', '/v1/team-availability/' + self.rid, person=2)['slots'], [])
        self.call('DELETE', '/v1/team-availability/' + self.rid, person=1)
        self.assertEqual(self.call('GET', path, person=1)['slots'], [])

    def test_feedback_waits_for_all_consent_and_never_shares_individual_feedback(self):
        team = self.create()
        self.review(self.apply(team, 1))
        self.call('POST', f"/v1/team-detail/{team['id']}/complete")
        path = f"/v1/team-detail/{team['id']}/feedback"
        answers = {'satisfaction': 5, 'efficiency': 4, 'willingAgain': True}
        self.assert_code('ALL_CONSENT_REQUIRED', lambda: self.call('POST', path, {'consent': True, 'answers': answers}))
        for person in (0, 1):
            self.call('POST', path, {'consent': True}, person=person)
        self.call('POST', path, {'consent': True, 'answers': answers})
        self.assertIsNone(self.call('GET', path, person=1)['answers'])
        self.assertIsNone(self.call('GET', path)['aggregate'])
        self.call('POST', path, {'consent': True, 'answers': dict(answers, satisfaction=3)}, person=1)
        self.assertEqual(self.call('GET', path)['aggregate']['satisfaction'], 4)
        self.assert_code('FEEDBACK_UNAVAILABLE', lambda: self.call('GET', path, person=2))
        self.call('POST', path, {'consent': False}, person=1)
        self.assertIsNone(self.call('GET', path)['aggregate'])

    def test_draft_without_answers_publish_requires_complete_and_enums_are_checked(self):
        with self.db.connect() as db:
            db.execute('DELETE FROM team_profiles WHERE user_id=?', (self.people[0]['user']['id'],))
            db.execute('DELETE FROM team_preferences WHERE user_id=?', (self.people[0]['user']['id'],))
        draft = self.create(publish=False)
        self.assert_code('QUESTIONNAIRE_REQUIRED', lambda: self.call('POST', f"/v1/team-detail/{draft['id']}/publish"))
        self.profile(0)
        self.preferences(0)
        self.call('POST', f"/v1/team-detail/{draft['id']}/publish")
        self.assertTrue(self.call('GET', '/v1/team-detail/' + draft['id'])['team']['published'])
        self.assert_code('ONE_TEAM_PER_ROUND', lambda: self.create())
        self.assert_code('VERSION_MISMATCH', lambda: self.call('PUT', '/v1/team-profile', {'answers': {}, 'questionnaireVersion': True}))

    def test_pagination_stable_filters_and_batch_query_count(self):
        self.create()
        b = self.create(person=1, collaborationMode='DEEP', requiredSkills=[{'tag': 'Q3_E', 'count': 1}])
        query = {'roundId': [self.rid], 'recommend': ['true'], 'limit': ['1']}
        first = self.call('GET', '/v1/team-list', query=query, person=2)
        self.assertEqual(first, self.call('GET', '/v1/team-list', query=query, person=2))
        self.assertEqual(first['next'], 1)
        second = self.call('GET', '/v1/team-list', query=dict(query, offset=['1']), person=2)
        self.assertNotEqual(first['teams'][0]['id'], second['teams'][0]['id'])
        self.assertIsNone(second['next'])
        filtered = self.call('GET', '/v1/team-list', query=dict(query, mode=['DEEP'], skill=['Q3_E']), person=2)
        self.assertEqual(filtered['teams'][0]['id'], b['id'])
        from contextlib import contextmanager
        queries = []
        original = self.db.connect
        @contextmanager
        def counted():
            with original() as db:
                db.set_trace_callback(queries.append)
                yield db
        self.db.connect = counted
        self.call('GET', '/v1/team-list', query=query, person=2)
        self.assertLessEqual(sum(sql.startswith('SELECT') for sql in queries), 12)

    def test_no_meeting_requirement_disables_availability_and_non_manager_changes_denied(self):
        team = self.create()
        self.assert_code('MEETING_NOT_REQUIRED', lambda: self.call('PUT', '/v1/team-availability/' + self.rid,
          {'consent': True, 'week': '2026-10-12', 'slots': [1]}, person=1))
        for operation in ('close', 'publish', 'complete', 'remove'):
            self.assert_code('LEADER_REQUIRED', lambda op=operation: self.call('POST', f"/v1/team-detail/{team['id']}/{op}",
              {'userId': self.people[2]['user']['id']} if op == 'remove' else {}, person=1))
        self.assert_code('MEMBER_NOT_FOUND', lambda: self.call('POST', f"/v1/team-detail/{team['id']}/leave", person=1))

    def test_course_default_is_shared_idempotent_and_legacy_creation_cannot_duplicate(self):
        for person in (0, 1, 2):
            current = self.call('POST', '/v1/team-default-round', {'offeringId': self.room}, person=person)['round']
            self.assertEqual(current['id'], self.rid)
        legacy = self.call('POST', '/v1/team-rounds', {'offeringId': self.room, 'name': '又一次活动'})
        self.assertEqual(legacy['id'], self.rid)
        self.assertEqual(len(self.call('GET', '/v1/team-rounds', query={'offeringId': [self.room]})['rounds']), 1)
        team = self.create()
        with self.db.connect() as db:
            db.execute('DELETE FROM team_default_rounds')  # Simulate pre-upgrade database.
        self.db = Database(self.db.file)
        self.assertEqual(self.call('POST', '/v1/team-default-round', {'offeringId': self.room})['round']['id'], self.rid)
        self.assertEqual(self.call('GET', '/v1/team-detail/' + team['id'])['team']['memberCount'], 1)
        self.assertEqual(self.call('GET', '/v1/team-preferences/' + self.rid)['answers']['q1'], 'Q1_A')

    def test_concurrent_first_visit_creates_one_default_scope(self):
        with self.db.connect() as db:
            db.execute('DELETE FROM team_default_rounds')
            db.execute('DELETE FROM team_preferences')
            db.execute('DELETE FROM group_rounds')
        barrier = threading.Barrier(2)
        ids, failures = [], []
        def visit(person):
            try:
                barrier.wait()
                ids.append(self.call('POST', '/v1/team-default-round', {'offeringId': self.room}, person=person)['round']['id'])
            except Exception as exc:
                failures.append(type(exc).__name__)
        threads = [threading.Thread(target=visit, args=(person,)) for person in (0, 1)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(10)
            self.assertFalse(thread.is_alive())
        self.assertEqual(failures, [])
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(set(ids)), 1)
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM group_rounds').fetchone()[0], 1)


if __name__ == '__main__':
    unittest.main()
