import sqlite3
import threading
import time
import unittest
from unittest.mock import patch
from app import ApiError
from room_events import RoomEvents
import test_chat as fixtures


class RoomEventTests(unittest.TestCase):
    setUp = fixtures.ChatTests.setUp
    call = fixtures.ChatTests.call

    def test_waiter_wakes_after_message_is_committed(self):
        entered = threading.Event()
        original_wait = self.db.events.wait
        result = []
        def wait(*args):
            entered.set()
            original_wait(*args)
        def reader():
            result.append(self.call('GET', self.path, query={'after':['0'],'wait':['8']}, token=self.b['token']))
        original_notify = self.db.events.notify
        visible = []
        def notify(room):
            other = sqlite3.connect(self.file)
            try:
                visible.append(other.execute('SELECT COUNT(*) FROM messages').fetchone()[0])
            finally:
                other.close()
            original_notify(room)
        with patch.object(self.db.events,'wait',side_effect=wait), patch.object(self.db.events,'notify',side_effect=notify):
            worker=threading.Thread(target=reader)
            worker.start()
            self.assertTrue(entered.wait(2))
            sent=self.call('POST',self.path,{'body':'wake up','clientId':'WAKE'})['message']
            worker.join(2)
            self.assertFalse(worker.is_alive())
        self.assertEqual(visible,[1])
        self.assertEqual(result[0]['messages'][0]['id'], sent['id'])

    def test_notification_between_snapshot_and_wait_is_not_lost(self):
        events=RoomEvents(redis_url='')
        generation=events.snapshot(self.room)
        events.notify(self.room)
        started=time.monotonic()
        events.wait(self.room,generation,2)
        self.assertLess(time.monotonic()-started,.5)
        events.close()

    def test_idle_wait_uses_two_queries_instead_of_repeated_quarter_second_polling(self):
        real_connect=sqlite3.connect
        queries=[]
        def connect(*args,**kwargs):
            conn=real_connect(*args,**kwargs)
            conn.set_trace_callback(lambda sql: queries.append(sql) if sql.startswith('SELECT e.id AS event_id') else None)
            return conn
        with patch('app.sqlite3.connect',side_effect=connect):
            result=self.call('GET',self.path,query={'after':['0'],'wait':['1']})
        self.assertEqual(result['messages'],[])
        self.assertEqual(len(queries),2)

    def test_notification_failure_does_not_undo_commit_and_invalid_write_does_not_notify(self):
        with patch.object(self.db.events,'notify',side_effect=RuntimeError('broker down')) as notify:
            with self.assertRaises(ApiError):
                self.call('POST',self.path,{'kind':'file','clientId':'INVALID'})
            notify.assert_not_called()
            sent=self.call('POST',self.path,{'body':'durable','clientId':'DURABLE'})['message']
            notify.assert_called_once_with(self.room)
        loaded=self.call('GET',self.path,query={'after':['0'],'wait':['0']})
        self.assertEqual(loaded['messages'][0]['id'],sent['id'])

    def test_outbox_is_bounded_even_when_broker_is_unavailable(self):
        events=RoomEvents(redis_url='')
        # Configure publishing without starting a worker to simulate a stuck broker.
        events.redis_url='unix:///unavailable'
        for _ in range(1000): events.notify(self.room)
        self.assertEqual(events.outbox.qsize(),128)
        self.assertEqual(events.snapshot(self.room),1000)
        events.close()
