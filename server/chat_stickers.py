"""Per-identity saved stickers, independent of the source message lifecycle."""
import hashlib
import re
import secrets
import time

import chat_media

NOT_HANDLED = object()


def initialize(db):
    db.execute('''CREATE TABLE IF NOT EXISTS saved_stickers (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
        data BLOB NOT NULL, mime TEXT NOT NULL, width INTEGER NOT NULL,
        height INTEGER NOT NULL, digest TEXT NOT NULL, created INTEGER NOT NULL,
        UNIQUE(user_id,digest))''')


def metadata(row):
    return {key: row[key] for key in ('id', 'width', 'height', 'created')}


def route(db, user, method, path, body, error):
    if path == '/v1/stickers':
        if method == 'GET':
            return {'stickers': [metadata(row) for row in db.execute(
                'SELECT id,width,height,created FROM saved_stickers WHERE user_id=? ORDER BY created DESC,id', (user['id'],))]}
        if method == 'POST':
            if ('media' in body) == ('messageId' in body):
                raise error(400, '请选择上传图片或添加消息里的表情包。')
            db.execute('BEGIN IMMEDIATE')
            if 'media' in body:
                data, width, height, mime = chat_media.parse(body['media'])
            else:
                mid = body['messageId']
                if isinstance(mid, bool) or not isinstance(mid, int) or mid < 1:
                    raise error(400, '消息标识无效。')
                source = db.execute('''SELECT a.data,a.mime,m.media_width,m.media_height
                    FROM message_media a JOIN messages m ON m.id=a.message_id
                    WHERE m.id=? AND m.recalled=0''', (mid,)).fetchone()
                if not source:
                    raise error(404, '图片不存在或消息已撤回。')
                data, mime, width, height = source
            digest = hashlib.sha256(data).hexdigest()
            existing = db.execute('SELECT * FROM saved_stickers WHERE user_id=? AND digest=?', (user['id'], digest)).fetchone()
            if existing:
                return {'sticker': metadata(existing)}
            count, used = db.execute('SELECT COUNT(*),COALESCE(SUM(length(data)),0) FROM saved_stickers WHERE user_id=?', (user['id'],)).fetchone()
            if count >= 200 or used + len(data) > 100 * 1024 * 1024:
                raise error(409, '收藏空间已满，请先移除部分表情包。')
            sid, created = secrets.token_hex(16), int(time.time())
            db.execute('INSERT INTO saved_stickers VALUES (?,?,?,?,?,?,?,?)', (sid, user['id'], data, mime, width, height, digest, created))
            return {'sticker': {'id': sid, 'width': width, 'height': height, 'created': created}}
    match = re.fullmatch(r'/v1/stickers/([a-f0-9]{32})(/media)?', path)
    if match:
        row = db.execute('SELECT * FROM saved_stickers WHERE id=? AND user_id=?', (match[1], user['id'])).fetchone()
        if not row:
            raise error(404, '表情包不存在或已移除。')
        if method == 'GET' and match[2]:
            return chat_media.MediaBytes(row['data'], row['mime'])
        if method == 'DELETE' and not match[2]:
            db.execute('DELETE FROM saved_stickers WHERE id=? AND user_id=?', (match[1], user['id']))
            return {'ok': True}
    return NOT_HANDLED
