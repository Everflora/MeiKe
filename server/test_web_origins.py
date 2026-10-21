import http.client
import tempfile
import threading
import unittest
from pathlib import Path
from app import Database, Server
from web_origins import parse_origins


class WebOriginTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Database(Path(self.temp.name) / 'test.sqlite3')
        self.server = Server(('127.0.0.1', 0), self.db,
                             web_origins='https://everflora.github.io')
        self.worker = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.worker.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.db.events.close()
        self.temp.cleanup()

    def request(self, method, headers, path='/health'):
        conn = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        try:
            conn.request(method, path, headers=headers)
            response = conn.getresponse()
            response.read()
            return response.status, dict(response.getheaders())
        finally:
            conn.close()

    def test_exact_origin_preflight_and_native_health(self):
        status, headers = self.request('OPTIONS', {
            'Origin': 'https://everflora.github.io',
            'Access-Control-Request-Method': 'POST',
            'Access-Control-Request-Headers': 'Authorization, Content-Type',
        })
        self.assertEqual(status, 204)
        self.assertEqual(headers['Access-Control-Allow-Origin'], 'https://everflora.github.io')
        self.assertNotIn('Access-Control-Allow-Credentials', headers)
        self.assertEqual(self.request('GET', {})[0], 200)
        status, headers = self.request('GET', {'Origin': 'https://everflora.github.io'})
        self.assertEqual(status, 200)
        self.assertIn('Retry-After', headers['Access-Control-Expose-Headers'])
        status, headers = self.request('GET', {
            'Origin': 'https://everflora.github.io'}, '/v1/profile')
        self.assertEqual(status, 401)
        self.assertEqual(headers['Access-Control-Allow-Origin'], 'https://everflora.github.io')

    def test_untrusted_or_null_origins_do_not_get_cors_access(self):
        for origin in ('null', 'https://evil.example', 'https://everflora.github.io.evil.example'):
            for method in ('GET', 'OPTIONS'):
                status, headers = self.request(method, {
                    'Origin': origin, 'Access-Control-Request-Method': 'POST'})
                self.assertEqual(status, 403)
                self.assertNotIn('Access-Control-Allow-Origin', headers)
        self.assertEqual(self.request('OPTIONS', {
            'Origin': 'https://everflora.github.io', 'Access-Control-Request-Method': 'PATCH'})[0], 403)

    def test_configuration_rejects_wildcards_credentials_paths_and_http(self):
        for origin in ('*', 'https://*.github.io', 'https://user@host.test',
                       'https://host.test/path', 'http://host.test', 'https://host.test?q=1'):
            with self.assertRaises(ValueError):
                parse_origins(origin)
        self.assertEqual(parse_origins(''), frozenset())
        self.assertIn('http://localhost:8842', parse_origins('http://localhost:8842'))
