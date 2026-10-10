import base64
import struct
import tempfile
import threading
import time
import unittest
import zlib
from pathlib import Path

from app import ApiError, Database


def png_avatar():
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    pixels = (b'\x00' + bytes((100, 180, 120, 255)) * 128) * 128
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 128, 128, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.file = Path(self.temp.name) / 'chat.sqlite3'
        self.db = Database(self.file)
        self.term = 'demo-term'
        self.db.import_catalog([{'termCode': self.term, 'name': '演示课程', 'identity': ['JXBID', 'DEMO-A']}])
        self.a = self.db.route('POST', '/v1/sessions', {}, {'name': '演示甲'}, '')
        self.b = self.db.route('POST', '/v1/sessions', {}, {'name': '演示乙'}, '')
        self.room = self.db.route('POST', '/v1/rooms/resolve', {}, {'termCode': self.term, 'identity': ['JXBID', 'DEMO-A']}, self.a['token'])['room']['roomKey']
        self.path = f'/v1/rooms/{self.room}/messages'

    def call(self, method, path, body=None, query=None, token=None):
        return self.db.route(method, path, query or {}, body or {}, self.a['token'] if token is None else token)

    def send(self, body='演示消息', client='CLIENT-A'):
        return self.call('POST', self.path, {'body': body, 'clientId': client})['message']

    def test_profile_and_avatar_persist_in_database_after_restart(self):
        image = png_avatar()
        profile = self.call('POST', '/v1/profile', {'name': '新昵称', 'avatar': base64.b64encode(image).decode()})
        self.db = Database(self.file)
        restored = self.call('GET', '/v1/profile')
        self.assertEqual(restored['name'], '新昵称')
        self.assertEqual(restored['id'], self.a['user']['id'])
        self.assertEqual(self.call('GET', '/v1/users/' + restored['id'] + '/avatar'), image)
        self.assertEqual(restored['avatarVersion'], profile['avatarVersion'])

    def test_upload_cannot_modify_other_users_profile_and_avatar_requires_token(self):
        self.call('POST', '/v1/profile', {'name': '演示新甲', 'id': self.b['user']['id']})
        self.assertEqual(self.call('GET', '/v1/profile', token=self.b['token'])['name'], '演示乙')
        with self.assertRaises(ApiError) as error:
            self.call('GET', '/v1/users/' + self.a['user']['id'] + '/avatar', token='')
        self.assertEqual(error.exception.status, 401)

    def test_bad_avatar_rejected_without_changing_profile(self):
        with self.assertRaises(ValueError):
            self.call('POST', '/v1/profile', {'name': '错误昵称', 'avatar': base64.b64encode(b'not-an-image').decode()})
        self.assertEqual(self.call('GET', '/v1/profile')['name'], '演示甲')

    def test_retry_is_idempotent_and_reused_id_with_other_content_rejected(self):
        first = self.send()
        second = self.send()
        self.assertEqual(first['id'], second['id'])
        with self.assertRaises(ApiError) as error:
            self.send('不同内容')
        self.assertEqual(error.exception.status, 409)
        self.assertEqual(len(self.call('GET', self.path)['messages']), 1)

    def test_chat_order_cursors_and_history_have_no_gaps(self):
        self.assertEqual(self.call('GET', self.path)['cursor'], 0)
        first = self.send(client='FIRST')
        initial = self.call('GET', self.path)
        second = self.send(client='SECOND')
        changes = self.call('GET', self.path, query={'after': [str(initial['cursor'])]})
        self.assertEqual([m['id'] for m in changes['messages']], [second['id']])
        self.assertGreater(changes['cursor'], initial['cursor'])
        history = self.call('GET', self.path, query={'before': [str(second['id'])]})
        self.assertEqual([m['id'] for m in history['messages']], [first['id']])

    def test_recall_and_profile_changes_reach_other_client(self):
        sent = self.send()
        initial = self.call('GET', self.path, token=self.b['token'])
        with self.assertRaises(ApiError):
            self.call('DELETE', f"/v1/messages/{sent['id']}", token=self.b['token'])
        self.call('POST', '/v1/profile', {'name': '新昵称'})
        changes = self.call('GET', self.path, query={'after': [str(initial['cursor'])]}, token=self.b['token'])
        self.assertEqual(changes['messages'][0]['name'], '新昵称')
        self.call('DELETE', f"/v1/messages/{sent['id']}")
        withdrawn = self.call('GET', self.path, query={'after': [str(changes['cursor'])]}, token=self.b['token'])
        self.assertTrue(withdrawn['messages'][0]['recalled'])
        self.assertEqual(withdrawn['messages'][0]['body'], '')

    def test_long_poll_receives_new_message_without_waiting_full_timeout(self):
        result = []
        thread = threading.Thread(target=lambda: result.append(self.call('GET', self.path, query={'after': ['0'], 'wait': ['2']}, token=self.b['token'])))
        thread.start()
        time.sleep(0.1)
        self.send()
        thread.join(timeout=1.5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(len(result[0]['messages']), 1)

    def test_legacy_posts_migrate_once_and_legacy_delete_is_synced(self):
        old = self.call('POST', f'/v1/rooms/{self.room}/posts', {'title': '旧标题', 'body': '旧内容'})['id']
        self.db = Database(self.file)
        self.db = Database(self.file)
        messages = self.call('GET', self.path)['messages']
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0]['body'], '旧标题\n旧内容')
        self.call('DELETE', f'/v1/posts/{old}')
        self.assertTrue(self.call('GET', self.path)['messages'][0]['recalled'])

    def test_message_report_saved_and_unknown_room_rejected(self):
        sent = self.send()
        self.call('POST', f"/v1/messages/{sent['id']}/report", {'reason': '演示举报'}, token=self.b['token'])
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM message_reports').fetchone()[0], 1)
        with self.assertRaises(ApiError):
            self.call('POST', '/v1/rooms/' + 'f' * 64 + '/messages', {'body': '演示', 'clientId': 'UNKNOWN'})


if __name__ == '__main__':
    unittest.main()
