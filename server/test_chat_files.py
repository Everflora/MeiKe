import base64
import http.client
import json
import threading
import unittest
from unittest.mock import patch
from app import ApiError, Database, Server
import test_chat as fixtures


class ChatFileTests(unittest.TestCase):
    setUp = fixtures.ChatTests.setUp
    call = fixtures.ChatTests.call

    def upload(self, data=b'course notes', name='课程资料.pdf', client='FILE-1'):
        return self.call('POST', self.path, {'kind': 'file', 'fileName': name,
            'media': base64.b64encode(data).decode(), 'clientId': client})['message']

    def test_metadata_bytes_restart_and_authenticated_download(self):
        sent = self.upload()
        self.assertEqual(sent['file'], {'name': '课程资料.pdf', 'size': 12})
        self.assertIsNone(sent['media'])
        self.assertEqual(sent['body'], '[文件] 课程资料.pdf')
        self.db = Database(self.file)
        url = f"/v1/messages/{sent['id']}/media"
        data = self.call('GET', url, token=self.b['token'])
        self.assertEqual(data, b'course notes')
        self.assertEqual(data.content_type, 'application/octet-stream')
        self.assertIn("filename*=UTF-8''%E8%AF%BE", data.content_disposition)
        with self.assertRaises(ApiError) as error:
            self.call('GET', url, token='')
        self.assertEqual(error.exception.status, 401)

    def test_retry_is_idempotent_and_filename_or_content_conflicts(self):
        original = self.upload()
        self.assertEqual(original, self.upload())
        for kwargs in ({'data': b'changed'}, {'name': '另一个文件.pdf'}):
            with self.assertRaises(ApiError) as error:
                self.upload(**kwargs)
            self.assertEqual(error.exception.status, 409)
        self.assertEqual(len(self.call('GET', self.path)['messages']), 1)

    def test_recall_deletes_bytes_but_does_not_allow_other_sender(self):
        sent = self.upload()
        url = f"/v1/messages/{sent['id']}"
        with self.assertRaises(ApiError) as error:
            self.call('DELETE', url, token=self.b['token'])
        self.assertEqual(error.exception.status, 403)
        self.call('DELETE', url)
        self.assertIsNone(self.call('GET', self.path)['messages'][0]['file'])
        with self.assertRaises(ApiError) as error:
            self.call('GET', url+'/media')
        self.assertEqual(error.exception.status, 404)
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM message_media').fetchone()[0], 0)

    def test_files_cannot_be_collected_as_stickers(self):
        sent = self.upload(data=b'<script>not an image</script>', name='notes.html')
        with self.assertRaises(ApiError):
            self.call('POST', '/v1/stickers', {'messageId': sent['id']})
        self.assertEqual(self.call('GET', '/v1/stickers')['stickers'], [])

    def test_names_content_limits_and_invalid_base64_do_not_create_messages(self):
        for name in ('../notes.txt', 'dir\\notes.txt', 'bad\r\nname.txt', '..', '', '字'*81):
            with self.assertRaises(ApiError):
                self.upload(name=name)
        with self.assertRaises(ApiError):
            self.upload(data=b'')
        with patch('chat_files.MAX_BYTES', 4):
            with self.assertRaises(ApiError) as error:
                self.upload(data=b'12345')
            self.assertEqual(error.exception.status, 413)
        with self.assertRaises(ApiError):
            self.call('POST', self.path, {'kind': 'file', 'fileName': 'file.txt', 'media': '**', 'clientId': 'BAD'})
        self.assertEqual(self.call('GET', self.path)['messages'], [])

    def test_http_upload_larger_than_image_limit_download_headers_and_recall(self):
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
            raw = b'x'*(4*1024*1024+1)
            status, _, body = request('POST', self.path, {'kind': 'file', 'fileName': '实验数据.zip',
                'media': base64.b64encode(raw).decode(), 'clientId': 'HTTP-FILE'}, self.a['token'])
            self.assertEqual(status, 200)
            sent = json.loads(body)['message']
            url = f"/v1/messages/{sent['id']}/media"
            self.assertEqual(request('GET', url)[0], 401)
            status, headers, data = request('GET', url, token=self.b['token'])
            self.assertEqual((status, data), (200, raw))
            self.assertEqual(headers['Content-Type'], 'application/octet-stream')
            self.assertTrue(headers['Content-Disposition'].startswith('attachment;'))
            self.assertEqual(headers['X-Content-Type-Options'], 'nosniff')
            self.assertEqual(request('DELETE', url[:-6], token=self.a['token'])[0], 200)
            self.assertEqual(request('GET', url, token=self.a['token'])[0], 404)
        finally:
            conn.close(); server.shutdown(); server.server_close(); worker.join(3)
