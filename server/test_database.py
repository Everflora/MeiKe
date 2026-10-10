import json
import tempfile
import unittest
from pathlib import Path
from app import ApiError, Database


class DatabaseTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.db = Database(Path(self.folder.name) / 'discussion.sqlite3')
        self.term = '2026-2027-2'
        self.room = {'termCode': self.term, 'termName': '秋季学期', 'name': '示例课程',
                     'identity': ['COURSE_TEACHER_CLASS', '示例课程', ['示例教师'], ['班级甲']],
                     'sourceIdentities': [['JXBID', 'PHASE-A'], ['JXBID', 'PHASE-B']]}

    def test_source_ids_resolve_to_same_room_and_reimport_is_idempotent(self):
        self.db.import_catalog([self.room])
        self.db.import_catalog([self.room])
        session = self.db.route('POST', '/v1/sessions', {}, {'name': '测试用户'}, '')
        resolved = [self.db.route('POST', '/v1/rooms/resolve', {},
                    {'termCode': self.term, 'identity': source}, session['token'])['room']['roomKey']
                    for source in self.room['sourceIdentities']]
        self.assertEqual(resolved[0], resolved[1])
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM rooms').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM identities').fetchone()[0], 3)

    def test_raw_records_keep_class_fields_and_map_to_room(self):
        self.db.import_catalog([self.room])
        rows = [{'WID': 'ROW-A', 'JXBID': 'PHASE-A', 'XNXQDM': self.term,
                 'SKBJ': '班级甲', 'BJXX': None, 'YPSJDD': '1-8周'},
                {'WID': 'ROW-B', 'JXBID': 'PHASE-B', 'XNXQDM': self.term,
                 'SKBJ': '班级甲', 'BJXX': None, 'YPSJDD': '9-16周'}]
        self.db.import_course_records({'termCode': self.term, 'totalCount': 2, 'rows': rows})
        with self.db.connect() as db:
            records = db.execute('SELECT room_id,data FROM course_records').fetchall()
            self.assertEqual(len({r['room_id'] for r in records}), 1)
            self.assertEqual(json.loads(records[0]['data'])['SKBJ'], '班级甲')
            self.assertEqual(db.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
            self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_conflicting_source_mapping_rolls_back_import(self):
        self.db.import_catalog([self.room])
        conflicting = dict(self.room, identity=['COURSE_TEACHER_CLASS', '示例课程', ['示例教师'], ['班级乙']])
        with self.assertRaises(ValueError):
            self.db.import_catalog([conflicting])
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM rooms').fetchone()[0], 1)

    def test_unmapped_raw_record_rolls_back_record_batch(self):
        self.db.import_catalog([self.room])
        rows = [{'WID': 'ROW-A', 'JXBID': 'PHASE-A', 'XNXQDM': self.term},
                {'WID': 'ROW-B', 'JXBID': 'UNKNOWN', 'XNXQDM': self.term}]
        with self.assertRaises(ValueError):
            self.db.import_course_records({'termCode': self.term, 'totalCount': 2, 'rows': rows})
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM course_records').fetchone()[0], 0)

    def test_matching_still_requires_identity(self):
        with self.assertRaises(ApiError) as error:
            self.db.route('POST', '/v1/rooms/match', {}, {}, '')
        self.assertEqual(error.exception.status, 401)

    def test_posts_replies_reports_and_own_delete(self):
        self.db.import_catalog([self.room])
        first = self.db.route('POST', '/v1/sessions', {}, {'name': '演示甲'}, '')['token']
        second = self.db.route('POST', '/v1/sessions', {}, {'name': '演示乙'}, '')['token']
        room = self.db.route('POST', '/v1/rooms/resolve', {},
                             {'termCode': self.term, 'identity': ['JXBID', 'PHASE-A']}, first)['room']['roomKey']
        path = '/v1/rooms/' + room + '/posts'
        post = self.db.route('POST', path, {}, {'title': '演示问题', 'body': '演示内容'}, first)['id']
        self.db.route('POST', path, {}, {'parent': post, 'body': '演示回复'}, second)
        feed = self.db.route('GET', path, {}, {}, second)['posts']
        self.assertEqual(feed[0]['replies'], 1)
        self.assertFalse(feed[0]['mine'])
        self.assertEqual(len(self.db.route('GET', path, {'parent': [str(post)]}, {}, first)['posts']), 1)
        self.db.route('POST', f'/v1/posts/{post}/report', {}, {'reason': '演示原因'}, second)
        with self.assertRaises(ApiError) as error:
            self.db.route('DELETE', f'/v1/posts/{post}', {}, {}, second)
        self.assertEqual(error.exception.status, 403)
        self.db.route('DELETE', f'/v1/posts/{post}', {}, {}, first)
        self.assertEqual(self.db.route('GET', path, {}, {}, first)['posts'], [])


if __name__ == '__main__':
    unittest.main()
