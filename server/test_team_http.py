"""Exercise the actual HTTP parser/handler without production identities."""
import http.client
import json
import tempfile
import threading
import unittest
from pathlib import Path
from app import Database, Server
from team_matching import CONFIG
from test_team_matching import full


class TeamHttpTests(unittest.TestCase):
    def test_authenticated_put_delete_and_identifiable_conflicts(self):
        with tempfile.TemporaryDirectory() as folder:
            database = Database(Path(folder) / 'isolated.sqlite3')
            database.import_catalog([{'termCode': 'TEST', 'name': 'HTTP测试', 'identity': ['JXBID', 'HTTP-TEST']}])
            server = Server(('127.0.0.1', 0), database)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=10)
            def request(method, path, body=None, token=''):
                headers = {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'}
                connection.request(method, path, json.dumps(body, ensure_ascii=False).encode() if body is not None else None, headers)
                response = connection.getresponse()
                return response.status, json.loads(response.read())
            try:
                self.assertEqual(request('GET', '/v1/team-config')[0], 401)
                _, session = request('POST', '/v1/sessions', {'name': 'HTTP测试身份'})
                token = session['token']
                self.assertEqual(request('GET', '/v1/team-config', token=token)[1]['config']['algorithmVersion'], 'rule-v1.0')
                _, resolved = request('POST', '/v1/rooms/resolve', {'termCode': 'TEST', 'identity': ['JXBID', 'HTTP-TEST']}, token)
                oid = resolved['room']['roomKey']
                self.assertEqual(request('POST', '/v1/team-consent', {'offeringId': oid, 'consent': True, 'confirmMembership': True}, token)[0], 200)
                _, group = request('POST', '/v1/team-rounds', {'offeringId': oid, 'name': 'HTTP任务'}, token)
                answers = full()
                for scope, path in [('profile', '/v1/team-profile'), ('round', '/v1/team-preferences/' + group['id'])]:
                    selected = {q['id']: answers[q['id']] for q in CONFIG['questions'] if q['scope'] == scope}
                    self.assertEqual(request('PUT', path, {'answers': selected, 'questionnaireVersion': 1}, token)[0], 200)
                status, created = request('POST', '/v1/team-list', {'roundId': group['id'], 'name': 'HTTP团队', 'capacity': 2, 'collaborationMode': 'LIGHT', 'needsMeeting': True}, token)
                self.assertEqual(status, 200)
                status, conflict = request('POST', '/v1/team-list', {'roundId': group['id'], 'name': '重复队', 'collaborationMode': 'LIGHT'}, token)
                self.assertEqual((status, conflict['code']), (409, 'ONE_TEAM_PER_ROUND'))
                path = '/v1/team-availability/' + group['id']
                self.assertEqual(request('PUT', path, {'consent': True, 'week': '2026-10-12', 'slots': [17]}, token)[0], 200)
                self.assertEqual(request('DELETE', path, token=token)[0], 200)
                self.assertFalse(request('GET', path, token=token)[1]['consent'])
                self.assertEqual(request('POST', '/v1/team-detail/' + created['team']['id'] + '/close', {}, token)[0], 200)
            finally:
                connection.close()
                server.shutdown()
                server.server_close()
                worker.join(3)


if __name__ == '__main__':
    unittest.main()
