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
from test_chat_media import gif_image, encoded, large_png


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
                database.import_catalog([{'termCode': 'TEST', 'name': '媒体测试', 'identity': ['JXBID', 'MEDIA-TEST']}])
                _, resolved = request('/v1/rooms/resolve', {'termCode': 'TEST', 'identity': ['JXBID', 'MEDIA-TEST']}, token)
                path = '/v1/rooms/' + resolved['room']['roomKey'] + '/messages'
                status, sent = request(path, {'kind': 'sticker', 'media': encoded(gif_image(2)), 'clientId': 'HTTP-GIF'}, token)
                self.assertEqual(status, 200)
                media_path = f"/v1/messages/{sent['message']['id']}/media"
                connection.request('GET', media_path, headers={'Authorization': 'Bearer ' + token})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.getheader('Content-Type'), 'image/gif')
                self.assertEqual(response.read(), gif_image(2))
                status, error = request(path, {'kind': 'image', 'media': encoded(b'bad'), 'clientId': 'HTTP-BAD'}, token)
                self.assertEqual((status, error['code']), (400, 'INVALID_MEDIA'))
                large = large_png()
                self.assertGreater(len(large), 150000)
                status, sent = request(path, {'kind': 'image', 'media': encoded(large), 'clientId': 'HTTP-LARGE'}, token)
                self.assertEqual(status, 200)
                connection.request('GET', f"/v1/messages/{sent['message']['id']}/media", headers={'Authorization': 'Bearer ' + token})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.getheader('Content-Type'), 'image/png')
                self.assertEqual(response.read(), large)
                status, saved = request('/v1/stickers', {'media': encoded(large)}, token)
                self.assertEqual(status, 200)
                sid = saved['sticker']['id']
                status, sent = request(path, {'kind': 'sticker', 'stickerId': sid, 'clientId': 'HTTP-SAVED'}, token)
                self.assertEqual(status, 200)
                connection.request('GET', '/v1/stickers/' + sid + '/media', headers={'Authorization': 'Bearer ' + token})
                response = connection.getresponse()
                self.assertEqual(response.status, 200)
                self.assertEqual(response.read(), large)

            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                worker.join(3)


if __name__ == '__main__':
    unittest.main()
