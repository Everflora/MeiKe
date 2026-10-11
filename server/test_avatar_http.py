"""Avatar errors reach clients without exposing unrelated validation internals."""
import base64
import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path

from app import Database, Server
from test_chat import png_avatar


class AvatarHttpTests(unittest.TestCase):
    def test_create_and_update_explain_avatar_errors_without_changing_profile(self):
        with tempfile.TemporaryDirectory() as folder:
            database = Database(Path(folder) / 'test.sqlite3')
            server = Server(('127.0.0.1', 0), database)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)

            def request(path, body, token=''):
                connection.request('POST', path, json.dumps(body).encode(),
                                   {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token})
                response = connection.getresponse()
                return response.status, json.loads(response.read())

            try:
                bad = {'name': '测试昵称', 'avatar': base64.b64encode(b'not-a-png').decode()}
                status, error = request('/v1/sessions', bad)
                self.assertEqual(status, 400)
                self.assertEqual(error, {'error': '请选择有效的头像图片。', 'code': 'INVALID_AVATAR'})
                with database.connect() as db:
                    self.assertEqual(db.execute('SELECT COUNT(*) FROM users').fetchone()[0], 0)
                status, session = request('/v1/sessions', {'name': '原昵称'})
                self.assertEqual(status, 200)
                token = session['token']
                status, error = request('/v1/profile', bad, token)
                self.assertEqual((status, error['code']), (400, 'INVALID_AVATAR'))
                self.assertEqual(database.route('GET', '/v1/profile', {}, {}, token)['name'], '原昵称')
                avatar = base64.b64encode(png_avatar()).decode()
                status, profile = request('/v1/profile', {'name': '新昵称', 'avatar': avatar}, token)
                self.assertEqual(status, 200)
                self.assertTrue(profile['avatarVersion'])
                status, error = request('/v1/sessions', {'name': '测试昵称', 'avatar': 'invalid base64'})
                self.assertEqual((status, error['error']), (400, '头像编码无效。'))
            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                worker.join(3)


if __name__ == '__main__':
    unittest.main()
