import base64
import random
import struct
import unittest
import zlib

from app import ApiError, Database
from chat_media import MediaError, MAX_BYTES, parse
import test_chat as fixtures
from test_chat import png_avatar


def gif_image(frames=1):
    # Two-colour 1×1 GIF; clear, pixel 0, end LZW codes.
    return (b'GIF89a' + struct.pack('<HHBBB', 1, 1, 128, 0, 0) + b'\x00\x00\x00\xff\xff\xff'
            + b'\x2c\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02\x44\x01\x00' * frames + b'\x3b')


def encoded(data):
    return base64.b64encode(data).decode()


def large_png():
    width, height = 768, 512
    random_bytes = random.Random(42).randbytes(width * height * 4)
    pixels = b''.join(b'\x00' + random_bytes[y * width * 4:(y + 1) * width * 4] for y in range(height))
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b''))


class MediaValidationTests(unittest.TestCase):
    def test_png_and_animated_gif(self):
        self.assertEqual(parse(encoded(png_avatar()))[1:], (128, 128, 'image/png'))
        self.assertEqual(parse(encoded(gif_image(2)))[1:], (1, 1, 'image/gif'))

    def test_size_corruption_truncation_and_dimensions(self):
        bad_png = bytearray(png_avatar())
        bad_png[-5] ^= 1
        oversized_gif = bytearray(gif_image())
        oversized_gif[6:8] = struct.pack('<H', 513)
        for bad in [None, 'not-base64!', encoded(b'<svg/>'), encoded(bad_png),
                    encoded(gif_image()[:-1]), encoded(oversized_gif),
                    encoded(gif_image(201)), encoded(b'x' * (MAX_BYTES + 1))]:
            with self.subTest(type=type(bad)), self.assertRaises(MediaError):
                parse(bad)


class ChatMediaTests(unittest.TestCase):
    setUp = fixtures.ChatTests.setUp
    call = fixtures.ChatTests.call

    def upload(self, data=None, kind='image', client='MEDIA-A'):
        return self.call('POST', self.path, {'kind': kind, 'media': encoded(data or png_avatar()), 'clientId': client})['message']

    def test_media_persists_and_history_has_metadata_only(self):
        sent = self.upload()
        self.assertEqual(sent['kind'], 'image')
        self.assertEqual(sent['media'], {'width': 128, 'height': 128})
        self.db = Database(self.file)
        self.assertEqual(self.call('GET', self.path)['messages'][0], sent)
        data = self.call('GET', f"/v1/messages/{sent['id']}/media", token=self.b['token'])
        self.assertEqual(data, png_avatar())
        self.assertEqual(data.content_type, 'image/png')
        with self.assertRaises(ApiError) as error:
            self.call('GET', f"/v1/messages/{sent['id']}/media", token='')
        self.assertEqual(error.exception.status, 401)

    def test_retry_and_conflicts_across_types_and_rooms(self):
        first = self.upload(gif_image(2), 'sticker')
        self.assertEqual(first, self.upload(gif_image(2), 'sticker'))
        self.assertEqual(self.call('GET', f"/v1/messages/{first['id']}/media").content_type, 'image/gif')
        with self.assertRaises(ApiError) as error:
            self.upload(gif_image(), 'sticker')
        self.assertEqual(error.exception.status, 409)
        with self.assertRaises(ApiError):
            self.upload(gif_image(2), 'image')
        with self.assertRaises(ApiError):
            self.call('POST', self.path, {'body': '[表情包]', 'clientId': 'MEDIA-A'})
        self.assertEqual(len(self.call('GET', self.path)['messages']), 1)

    def test_recall_removes_bytes_and_announces_to_other_client(self):
        sent = self.upload()
        cursor = self.call('GET', self.path)['cursor']
        with self.assertRaises(ApiError) as error:
            self.call('DELETE', f"/v1/messages/{sent['id']}", token=self.b['token'])
        self.assertEqual(error.exception.status, 403)
        self.call('DELETE', f"/v1/messages/{sent['id']}")
        update = self.call('GET', self.path, query={'after': [str(cursor)]})['messages'][0]
        self.assertTrue(update['recalled'])
        self.assertIsNone(update['media'])
        with self.assertRaises(ApiError) as error:
            self.call('GET', f"/v1/messages/{sent['id']}/media")
        self.assertEqual(error.exception.status, 404)
        with self.db.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM message_media').fetchone()[0], 0)

    def test_invalid_media_rolls_back_and_rate_limit_allows_retry(self):
        with self.assertRaises(MediaError):
            self.call('POST', self.path, {'kind': 'image', 'media': encoded(b'invalid'), 'clientId': 'BAD'})
        self.assertEqual(self.call('GET', self.path)['messages'], [])
        first = self.upload()
        for number in range(9):
            self.upload(client=f'NEXT-{number}')
        with self.assertRaises(ApiError) as error:
            self.upload(client='OVER-LIMIT')
        self.assertEqual(error.exception.status, 429)
        self.assertEqual(self.upload()['id'], first['id'])

    def test_existing_text_and_repeated_migrations_remain_compatible(self):
        text = self.call('POST', self.path, {'body': '原有文字', 'clientId': 'TEXT'})['message']
        self.assertEqual(text['kind'], 'text')
        self.assertIsNone(text['media'])
        self.upload()
        self.db = Database(self.file)
        self.db = Database(self.file)
        self.assertEqual(len(self.call('GET', self.path)['messages']), 2)


if __name__ == '__main__':
    unittest.main()
