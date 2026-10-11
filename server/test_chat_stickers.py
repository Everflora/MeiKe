import unittest

from app import ApiError, Database
import test_chat as fixtures
from test_chat_media import encoded, gif_image


class StickerTests(unittest.TestCase):
    setUp = fixtures.ChatTests.setUp
    call = fixtures.ChatTests.call

    def add(self, token=None):
        return self.call('POST', '/v1/stickers', {'media': encoded(gif_image(2))}, token=token)['sticker']

    def send(self, sticker, client='SAVED'):
        return self.call('POST', self.path, {'kind': 'sticker', 'stickerId': sticker['id'], 'clientId': client})['message']

    def test_upload_list_duplicate_restart_and_send_retry(self):
        sticker = self.add()
        self.assertEqual(sticker, self.add())
        self.db = Database(self.file)
        self.assertEqual(self.call('GET', '/v1/stickers')['stickers'], [sticker])
        sent = self.send(sticker)
        self.assertEqual(sent, self.send(sticker))
        self.assertEqual(sent['kind'], 'sticker')
        self.assertEqual(self.call('GET', f"/v1/messages/{sent['id']}/media"), gif_image(2))

    def test_collection_private_read_delete_and_send(self):
        sticker = self.add()
        path = '/v1/stickers/' + sticker['id']
        self.assertEqual(self.call('GET', '/v1/stickers', token=self.b['token'])['stickers'], [])
        for method, route in [('GET', path + '/media'), ('DELETE', path)]:
            with self.assertRaises(ApiError) as error:
                self.call(method, route, token=self.b['token'])
            self.assertEqual(error.exception.status, 404)
        with self.assertRaises(ApiError):
            self.call('POST', self.path, {'kind': 'sticker', 'stickerId': sticker['id'], 'clientId': 'STEAL'}, token=self.b['token'])
        with self.assertRaises(ApiError) as error:
            self.call('GET', '/v1/stickers', token='')
        self.assertEqual(error.exception.status, 401)

    def test_add_others_message_survives_source_recall(self):
        original = self.send(self.add())
        copied = self.call('POST', '/v1/stickers', {'messageId': original['id']}, token=self.b['token'])['sticker']
        self.call('DELETE', f"/v1/messages/{original['id']}")
        self.assertEqual(self.call('GET', '/v1/stickers/' + copied['id'] + '/media', token=self.b['token']), gif_image(2))
        with self.assertRaises(ApiError):
            self.call('POST', '/v1/stickers', {'messageId': original['id']})

    def test_remove_saved_sticker_preserves_sent_messages(self):
        sticker = self.add()
        sent = self.send(sticker)
        self.call('DELETE', '/v1/stickers/' + sticker['id'])
        self.assertEqual(self.call('GET', '/v1/stickers')['stickers'], [])
        self.assertEqual(self.call('GET', f"/v1/messages/{sent['id']}/media"), gif_image(2))
        with self.assertRaises(ApiError):
            self.send(sticker, 'NEW')

    def test_ambiguous_or_invalid_input_rejected(self):
        for body in [{}, {'media': encoded(gif_image()), 'messageId': 1}, {'messageId': True}, {'messageId': '1'}, {'messageId': -1}, {'messageId': 9999}]:
            with self.subTest(body=body), self.assertRaises(ApiError):
                self.call('POST', '/v1/stickers', body)
        self.assertEqual(self.call('GET', '/v1/stickers')['stickers'], [])

    def test_collection_limit_and_duplicate_at_capacity(self):
        sticker = self.add()
        with self.db.connect() as db:
            row = db.execute('SELECT * FROM saved_stickers WHERE id=?', (sticker['id'],)).fetchone()
            for i in range(199):
                db.execute('INSERT INTO saved_stickers VALUES (?,?,?,?,?,?,?,?)',
                           (f'{i:032x}', row['user_id'], row['data'], row['mime'], row['width'], row['height'], f'fixture-{i}', row['created']))
        self.assertEqual(self.add(), sticker)
        with self.assertRaises(ApiError) as error:
            self.call('POST', '/v1/stickers', {'media': encoded(gif_image())})
        self.assertEqual(error.exception.status, 409)
        self.call('DELETE', '/v1/stickers/' + sticker['id'])
        self.assertEqual(len(self.call('GET', '/v1/stickers')['stickers']), 199)


if __name__ == '__main__':
    unittest.main()
