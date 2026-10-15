"""New file uploads are disabled; historical attachments remain readable."""
import base64
import hashlib
import http.client
import json
import threading
import time
import unittest
from app import ApiError, Server
import test_chat as fixtures
from test_chat_media import gif_image


class ChatFileTests(unittest.TestCase):
    setUp = fixtures.ChatTests.setUp
    call = fixtures.ChatTests.call

    def historical_file(self, data=b'course notes', name='课程资料.pdf'):
        with self.db.connect() as db:
            cur = db.execute("""INSERT INTO messages
                (room_id,user_id,body,created,client_id,kind,file_name,file_size,media_hash)
                VALUES (?,?,?,?,?,?,?,?,?)""", (self.room, self.a['user']['id'], '[文件] '+name,
                int(time.time()), 'LEGACY-FILE', 'file', name, len(data), hashlib.sha256(data).hexdigest()))
            mid = cur.lastrowid
            db.execute('INSERT INTO message_media VALUES (?,?,?)', (mid, data, 'application/octet-stream'))
            db.execute('INSERT INTO message_events(room_id,message_id) VALUES (?,?)', (self.room, mid))
        return mid

    def test_file_upload_rejected_without_creating_messages_or_media(self):
        for media in [base64.b64encode(b'notes').decode(), '**', '']:
            with self.assertRaises(ApiError) as caught:
                self.call('POST', self.path, {'kind': 'file', 'fileName': 'notes.pdf',
                    'media': media, 'clientId': 'NEW-FILE'})
            self.assertEqual((caught.exception.status, caught.exception.code), (400, 'FILE_UPLOAD_DISABLED'))
        self.assertEqual(self.call('GET', self.path)['messages'], [])
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM message_media').fetchone()[0], 0)

    def test_historical_files_remain_authenticated_downloadable_and_recallable(self):
        mid = self.historical_file()
        url = f'/v1/messages/{mid}/media'
        self.assertEqual(self.call('GET', self.path)['messages'][0]['file']['size'], 12)
        with self.assertRaises(ApiError) as caught:
            self.call('GET', url, token='')
        self.assertEqual(caught.exception.status, 401)
        self.assertEqual(self.call('GET', url, token=self.b['token']), b'course notes')
        with self.assertRaises(ApiError):
            self.call('POST', '/v1/stickers', {'messageId': mid})
        with self.assertRaises(ApiError):
            self.call('DELETE', f'/v1/messages/{mid}', token=self.b['token'])
        self.call('DELETE', f'/v1/messages/{mid}')
        with self.assertRaises(ApiError) as caught:
            self.call('GET', url)
        self.assertEqual(caught.exception.status, 404)

    def test_http_blocks_old_client_upload_but_keeps_gif_and_legacy_download(self):
        mid = self.historical_file()
        server = Server(('127.0.0.1', 0), self.db)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        conn = http.client.HTTPConnection(*server.server_address, timeout=15)
        def request(method, path, body=None, token=None):
            headers = {'Content-Type': 'application/json'}
            if token: headers['Authorization'] = 'Bearer '+token
            conn.request(method, path, json.dumps(body).encode() if body is not None else None, headers)
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        try:
            status, _, body = request('POST', self.path, {'kind': 'file', 'fileName': 'data.zip',
                'media': base64.b64encode(b'x'*(4*1024*1024)).decode(), 'clientId': 'HTTP-FILE'}, self.a['token'])
            self.assertEqual(status, 400)
            self.assertEqual(json.loads(body)['code'], 'FILE_UPLOAD_DISABLED')
            raw = gif_image(2)
            status, _, body = request('POST', self.path, {'kind': 'sticker',
                'media': base64.b64encode(raw).decode(), 'clientId': 'HTTP-GIF'}, self.a['token'])
            self.assertEqual(status, 200)
            gif_id = json.loads(body)['message']['id']
            self.assertEqual(request('GET', f'/v1/messages/{gif_id}/media', token=self.b['token'])[2], raw)
            url = f'/v1/messages/{mid}/media'
            self.assertEqual(request('GET', url)[0], 401)
            status, headers, data = request('GET', url, token=self.b['token'])
            self.assertEqual((status, data), (200, b'course notes'))
            self.assertEqual(headers['Content-Type'], 'application/octet-stream')
            self.assertTrue(headers['Content-Disposition'].startswith('attachment;'))
        finally:
            conn.close(); server.shutdown(); server.server_close(); worker.join(3)
