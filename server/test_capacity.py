import base64
import http.client
import json
import threading
import time
import unittest
from unittest.mock import patch
from app import Server
from capacity import CapacityLimits
import test_chat as fixtures
from test_chat_media import gif_image


class CapacityTests(unittest.TestCase):
    setUp = fixtures.ChatTests.setUp

    def server(self, **limits):
        if 'requests' in limits:
            limits.setdefault('polls', max(0, limits['requests']-1))
        server = Server(('127.0.0.1', 0), self.db, CapacityLimits(**limits))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        self.addCleanup(lambda: (server.shutdown(), server.server_close(), worker.join(3)))
        return server

    def connection(self, server):
        conn = http.client.HTTPConnection(*server.server_address, timeout=3)
        self.addCleanup(conn.close)
        return conn

    def request(self, conn, path, body=None):
        conn.request('POST' if body is not None else 'GET', path,
                     json.dumps(body).encode() if body is not None else None,
                     {'Authorization': 'Bearer '+self.a['token'], 'Content-Type': 'application/json'})
        response = conn.getresponse()
        return response.status, dict(response.getheaders()), response.read()

    def test_capacity_validation_and_environment(self):
        for values in [{'connections':0}, {'requests':161}, {'uploads':129}, {'retry_after':31}]:
            with self.assertRaises(ValueError): CapacityLimits(**values)
        with patch.dict('os.environ', {'MEIKE_MAX_BACKLOG':'200', 'MEIKE_MAX_UPLOADS':'2'}):
            limits=CapacityLimits.from_environment()
            self.assertEqual((limits.backlog, limits.uploads), (200, 2))

    def test_connection_cap_rejects_without_extra_threads_and_recovers(self):
        server=self.server(connections=2, requests=2, downloads=1)
        held=[self.connection(server) for _ in range(2)]
        for conn in held: self.assertEqual(self.request(conn,'/health')[0],200)
        extra=self.connection(server)
        status,headers,data=self.request(extra,'/health')
        self.assertEqual((status,headers['Retry-After'],json.loads(data)['code']), (503,'3','SERVER_BUSY'))
        self.assertEqual(headers['Connection'], 'close')
        held[0].close()
        for _ in range(30):
            if server.connection_slots.acquire(False):
                server.connection_slots.release()
                break
            time.sleep(.01)
        self.assertEqual(self.request(extra,'/health')[0],200)

    def test_request_cap_preserves_health_and_releases_after_error(self):
        server=self.server(requests=1, downloads=1)
        conn=self.connection(server)
        server.request_slots.acquire()
        try:
            status,headers,data=self.request(conn,'/v1/profile')
            self.assertEqual((status,headers['Retry-After'],json.loads(data)['code']), (503,'3','SERVER_BUSY'))
            self.assertEqual(self.request(conn,'/health')[0],200)
        finally: server.request_slots.release()
        self.assertEqual(self.request(conn,'/v1/profile')[0],200)
        self.assertEqual(self.request(conn,'/not-found')[0],404)
        self.assertEqual(self.request(conn,'/v1/profile')[0],200)

    def test_upload_gate_before_large_body_read_and_saved_sticker_gate(self):
        server=self.server()
        conn=self.connection(server)
        raw=gif_image(2)
        body={'kind':'sticker','media':base64.b64encode(raw).decode(),'clientId':'CAPACITY-GIF'}
        saved=self.db.route('POST','/v1/stickers',{}, {'media':body['media']},self.a['token'])['sticker']
        server.upload_slots.acquire()
        try:
            # No body is sent: a rejected large upload must respond immediately.
            conn.putrequest('POST',self.path)
            conn.putheader('Content-Length','200000')
            conn.endheaders()
            response=conn.getresponse()
            self.assertEqual((response.status,json.loads(response.read())['code']), (503,'UPLOAD_BUSY'))
            for path, value in [(self.path,body),('/v1/stickers',{'media':body['media']}),
                    (self.path,{'kind':'sticker','stickerId':saved['id'],'clientId':'SAVED'})]:
                status,_,data=self.request(conn,path,value)
                self.assertEqual((status,json.loads(data)['code']), (503,'UPLOAD_BUSY'))
            large={**body,'media':base64.b64encode(b'x'*(4*1024*1024)).decode()}
            status,headers,data=self.request(conn,self.path,large)
            self.assertEqual((status,headers['Retry-After'],json.loads(data)['code']), (503,'3','UPLOAD_BUSY'))
            self.assertEqual(self.request(conn,self.path)[0],200)
            self.assertEqual(self.db.route('GET',self.path,{}, {},self.a['token'])['messages'],[])
        finally: server.upload_slots.release()
        invalid={**body,'media':'invalid'}
        self.assertEqual(self.request(conn,self.path,invalid)[0],400)
        self.assertEqual(self.request(conn,self.path,body)[0],200)
        self.assertEqual(self.request(conn,self.path,{'kind':'sticker','stickerId':saved['id'],'clientId':'SAVED'})[0],200)

    def test_download_gate_recovers_and_binary_response_remains_valid(self):
        server=self.server()
        conn=self.connection(server)
        raw=gif_image(2)
        message=self.db.route('POST',self.path,{}, {'kind':'sticker',
            'media':base64.b64encode(raw).decode(),'clientId':'DOWNLOAD'},self.a['token'])['message']
        path=f"/v1/messages/{message['id']}/media"
        for _ in range(server.limits.downloads): server.download_slots.acquire()
        try:
            status,_,data=self.request(conn,path)
            self.assertEqual((status,json.loads(data)['code']), (503,'DOWNLOAD_BUSY'))
        finally:
            for _ in range(server.limits.downloads): server.download_slots.release()
        status,headers,data=self.request(conn,path)
        self.assertEqual((status,headers['Content-Type'],data), (200,'image/gif',raw))

    def test_full_long_poll_capacity_still_accepts_message_send(self):
        server=self.server(connections=8,requests=4,polls=2)
        readers=[self.connection(server) for _ in range(2)]
        writer=self.connection(server)
        waiting=threading.Event()
        gate=threading.Lock()
        entered=0
        results=[]
        original=self.db.events.wait
        def wait(*args):
            nonlocal entered
            with gate:
                entered+=1
                if entered==2: waiting.set()
            original(*args)
        def poll(conn):
            results.append(self.request(conn,self.path+'?after=0&wait=8'))
        with patch.object(self.db.events,'wait',side_effect=wait):
            workers=[threading.Thread(target=poll,args=(conn,)) for conn in readers]
            for worker in workers: worker.start()
            self.assertTrue(waiting.wait(2))
            status,_,data=self.request(writer,self.path+'?after=0&wait=8')
            self.assertEqual((status,json.loads(data)['code']), (503,'POLL_BUSY'))
            self.assertEqual(self.request(writer,self.path,{'body':'reserved capacity','clientId':'RESERVED'})[0],200)
            for worker in workers:
                worker.join(2)
                self.assertFalse(worker.is_alive())
        self.assertEqual([result[0] for result in results],[200,200])
