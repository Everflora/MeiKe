"""Bounded wake-up notifications; committed SQLite events remain authoritative."""
import os
import queue
import re
import threading


class RoomEvents:
    CHANNEL = 'meike:chat:wakeup:v1'

    def __init__(self, redis_url=None):
        self.conditions = [threading.Condition() for _ in range(64)]
        self.generations = [0]*64
        self.stop = threading.Event()
        self.ready = threading.Event()
        self.outbox = queue.Queue(maxsize=128)
        self.threads = []
        self.redis_url = redis_url if redis_url is not None else os.environ.get('MEIKE_REDIS_URL', '')
        if self.redis_url:
            try:
                import redis
                from redis.backoff import NoBackoff
                from redis.retry import Retry
                options = dict(max_connections=1, socket_connect_timeout=.2,
                               retry=Retry(NoBackoff(), 0), decode_responses=False)
                self.publisher = redis.Redis.from_url(self.redis_url, socket_timeout=.2, **options)
                self.subscriber = redis.Redis.from_url(self.redis_url, socket_timeout=2, **options)
                for target in (self.publish_loop, self.subscribe_loop):
                    thread = threading.Thread(target=target, daemon=True, name='meike-notify')
                    self.threads.append(thread)
                    thread.start()
            except ImportError:
                # No Redis dependency is needed for offline development.
                self.redis_url = ''

    @property
    def mode(self):
        return 'redis' if self.ready.is_set() else 'local'

    @staticmethod
    def bucket(room):
        return int(room[:8], 16) % 64

    def snapshot(self, room):
        index = self.bucket(room)
        with self.conditions[index]:
            return self.generations[index]

    def wait(self, room, generation, timeout):
        index = self.bucket(room)
        with self.conditions[index]:
            self.conditions[index].wait_for(
                lambda: self.generations[index] != generation or self.stop.is_set(), timeout)

    def signal(self, room):
        indexes = range(64) if room == '*' else [self.bucket(room)]
        for index in indexes:
            with self.conditions[index]:
                self.generations[index] += 1
                self.conditions[index].notify_all()

    def notify(self, room):
        self.signal(room)
        if self.redis_url and not self.stop.is_set():
            try:
                self.outbox.put_nowait(room)
            except queue.Full:
                # Never accumulate messages or block a successful database commit.
                # Other processes will catch up from their cursor on timeout.
                pass

    def publish_loop(self):
        try:
            while not self.stop.is_set():
                try:
                    room = self.outbox.get(timeout=.2)
                except queue.Empty:
                    continue
                try:
                    self.publisher.publish(self.CHANNEL, room)
                except Exception:
                    self.stop.wait(.5)
                finally:
                    self.outbox.task_done()
        finally:
            self.publisher.close()

    def subscribe_loop(self):
        try:
            while not self.stop.is_set():
                pubsub = None
                try:
                    pubsub = self.subscriber.pubsub()
                    pubsub.subscribe(self.CHANNEL)
                    while not self.stop.is_set():
                        event = pubsub.get_message(timeout=1)
                        if not event:
                            continue
                        if event['type'] == 'subscribe':
                            self.ready.set()
                        elif event['type'] == 'message':
                            data = event['data']
                            if isinstance(data, bytes) and (data == b'*' or re.fullmatch(b'[a-f0-9]{64}', data)):
                                self.signal(data.decode('ascii'))
                except Exception:
                    was_ready = self.ready.is_set()
                    self.ready.clear()
                    if was_ready:
                        self.signal('*')
                    self.stop.wait(1)
                finally:
                    if pubsub is not None:
                        pubsub.close()
        finally:
            self.subscriber.close()
            self.ready.clear()

    def close(self):
        self.stop.set()
        self.signal('*')
        for thread in self.threads:
            thread.join(2)
