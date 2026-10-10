"""Authenticated chat, editable profiles and avatars stored in SQLite."""
import base64
import binascii
import hashlib
import json
import re
import struct
import time
import zlib


NOT_HANDLED = object()


def avatar_bytes(value):
    if value is None:
        return None
    if not isinstance(value, str) or len(value) > 131072:
        raise ValueError('头像文件过大。')
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        raise ValueError('头像编码无效。') from None
    if len(data) > 98304 or not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('请选择有效的头像图片。')
    position, compressed, header, ended = 8, b'', None, False
    while position + 12 <= len(data):
        size = struct.unpack('>I', data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        end = position + 12 + size
        if end > len(data):
            raise ValueError('头像图片不完整。')
        part = data[position + 8:position + 8 + size]
        checksum = struct.unpack('>I', data[end - 4:end])[0]
        if zlib.crc32(kind + part) & 0xffffffff != checksum:
            raise ValueError('头像图片校验失败。')
        if kind == b'IHDR':
            if header is not None or position != 8 or size != 13:
                raise ValueError('头像图片头无效。')
            header = struct.unpack('>IIBBBBB', part)
        elif kind == b'IDAT':
            compressed += part
        elif kind == b'IEND':
            if size != 0 or end != len(data):
                raise ValueError('头像图片结尾无效。')
            ended = True
        position = end
    if (not ended or not header or header[:3] != (128, 128, 8)
            or header[3] not in (2, 6) or header[4:] != (0, 0, 0)):
        raise ValueError('头像需要由应用转换成 128×128 PNG 图片。')
    try:
        decoder = zlib.decompressobj()
        expected = 128 * (128 * (4 if header[3] == 6 else 3) + 1)
        pixels = decoder.decompress(compressed, expected + 1)
        if len(pixels) != expected or not decoder.eof or decoder.unused_data:
            raise ValueError('头像像素数据无效。')
    except zlib.error:
        raise ValueError('头像像素数据无效。') from None
    return data


def profile(row):
    return {'id': row['id'], 'name': row['name'], 'avatarVersion': row['avatar_version']}


def initialize(db):
    columns = {row['name'] for row in db.execute('PRAGMA table_info(users)')}
    if 'avatar' not in columns:
        db.execute('ALTER TABLE users ADD COLUMN avatar BLOB')
    if 'avatar_version' not in columns:
        db.execute("ALTER TABLE users ADD COLUMN avatar_version TEXT NOT NULL DEFAULT ''")
    db.executescript('''
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          room_id TEXT NOT NULL REFERENCES rooms(id),
          user_id TEXT NOT NULL REFERENCES users(id),
          body TEXT NOT NULL, created INTEGER NOT NULL,
          recalled INTEGER NOT NULL DEFAULT 0, client_id TEXT NOT NULL,
          UNIQUE(user_id, client_id));
        CREATE INDEX IF NOT EXISTS messages_room ON messages(room_id, id);
        CREATE INDEX IF NOT EXISTS messages_user_time ON messages(user_id, created);
        CREATE TABLE IF NOT EXISTS message_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          room_id TEXT NOT NULL REFERENCES rooms(id),
          message_id INTEGER NOT NULL REFERENCES messages(id));
        CREATE INDEX IF NOT EXISTS message_events_room ON message_events(room_id, id);
        CREATE TABLE IF NOT EXISTS message_reports (
          message_id INTEGER NOT NULL REFERENCES messages(id),
          user_id TEXT NOT NULL REFERENCES users(id), reason TEXT NOT NULL,
          PRIMARY KEY(message_id, user_id));
    ''')
    for post in db.execute('SELECT * FROM posts ORDER BY id').fetchall():
        mirror_post(db, post)


def mirror_post(db, post):
    body = '\n'.join(part for part in (post['title'], post['body']) if part)
    cursor = db.execute('INSERT OR IGNORE INTO messages(room_id,user_id,body,created,recalled,client_id) VALUES (?,?,?,?,?,?)',
                        (post['room_id'], post['user_id'], body, post['created'], post['deleted'], f"legacy-post:{post['id']}"))
    if cursor.rowcount:
        db.execute('INSERT INTO message_events(room_id,message_id) VALUES (?,?)', (post['room_id'], cursor.lastrowid))


def recall_legacy(db, post_id):
    posts = db.execute('SELECT id,user_id FROM posts WHERE id=? OR parent_id=?', (post_id, post_id)).fetchall()
    for post in posts:
        old = db.execute('SELECT id,room_id,recalled FROM messages WHERE user_id=? AND client_id=?',
                         (post['user_id'], f"legacy-post:{post['id']}")).fetchone()
        if old and not old['recalled']:
            db.execute('UPDATE messages SET recalled=1 WHERE id=?', (old['id'],))
            db.execute('INSERT INTO message_events(room_id,message_id) VALUES (?,?)', (old['room_id'], old['id']))


def message(row, user):
    return {'id': row['id'], 'userId': row['user_id'], 'name': row['name'],
            'avatarVersion': row['avatar_version'], 'body': '' if row['recalled'] else row['body'],
            'created': row['created'], 'recalled': bool(row['recalled']),
            'mine': row['user_id'] == user['id'], 'clientId': row['client_id']}


SELECT_MESSAGE = 'SELECT m.*,u.name,u.avatar_version FROM messages m JOIN users u ON u.id=m.user_id '


def route(db, user, method, path, query, body, error, bounded):
    if path == '/v1/profile':
        if method == 'GET':
            return profile(user)
        if method == 'POST':
            name = bounded(body.get('name'), '昵称', 24)
            if 'avatar' in body:
                avatar = avatar_bytes(body['avatar'])
                version = hashlib.sha256(avatar).hexdigest() if avatar else ''
                db.execute('UPDATE users SET name=?,avatar=?,avatar_version=? WHERE id=?',
                           (name, avatar, version, user['id']))
            else:
                db.execute('UPDATE users SET name=? WHERE id=?', (name, user['id']))
            # Refresh names/avatars on messages already visible to other clients.
            db.execute('INSERT INTO message_events(room_id,message_id) SELECT room_id,id FROM messages WHERE user_id=?', (user['id'],))
            return profile(db.execute('SELECT id,name,avatar_version FROM users WHERE id=?', (user['id'],)).fetchone())
    avatar_match = re.fullmatch(r'/v1/users/([a-f0-9]{32})/avatar', path)
    if method == 'GET' and avatar_match:
        row = db.execute('SELECT avatar,avatar_version FROM users WHERE id=?', (avatar_match[1],)).fetchone()
        if not row or not row['avatar'] or query.get('version', [row['avatar_version']])[0] != row['avatar_version']:
            raise error(404, '头像不存在或已更新。')
        return row['avatar']
    room_match = re.fullmatch(r'/v1/rooms/([a-f0-9]{64})/messages', path)
    if room_match:
        room = room_match[1]
        if not db.execute('SELECT 1 FROM rooms WHERE id=?', (room,)).fetchone():
            raise error(404, '讨论室不存在。')
        if method == 'GET':
            after = query.get('after', [None])[0]
            before = query.get('before', [None])[0]
            if after is not None and before is not None:
                raise error(400, '不能同时加载历史和新消息。')
            if after is not None:
                after = int(after)
                wait = float(query.get('wait', ['0'])[0])
                if after < 0 or not 0 <= wait <= 8:
                    raise error(400, '消息游标无效。')
                deadline = time.monotonic() + wait
                while True:
                    changes = db.execute('''SELECT e.id AS event_id,m.*,u.name,u.avatar_version
                        FROM message_events e JOIN messages m ON m.id=e.message_id
                        JOIN users u ON u.id=m.user_id WHERE e.room_id=? AND e.id>? ORDER BY e.id LIMIT 100''', (room, after)).fetchall()
                    if changes or time.monotonic() >= deadline:
                        return {'messages': [message(row, user) for row in changes],
                                'cursor': changes[-1]['event_id'] if changes else after, 'before': None}
                    time.sleep(min(0.25, max(0, deadline - time.monotonic())))
            before = int(before) if before is not None else 9223372036854775807
            if before < 1:
                raise error(400, '历史消息游标无效。')
            rows = db.execute('''SELECT m.*,u.name,u.avatar_version,
                (SELECT COALESCE(MAX(id),0) FROM message_events WHERE room_id=?) AS cursor
                FROM messages m JOIN users u ON u.id=m.user_id
                WHERE m.room_id=? AND m.id<? ORDER BY m.id DESC LIMIT 50''', (room, room, before)).fetchall()
            return {'messages': [message(row, user) for row in reversed(rows)],
                    'cursor': rows[0]['cursor'] if rows else 0,
                    'before': rows[-1]['id'] if len(rows) == 50 else None}
        if method == 'POST':
            content = bounded(body.get('body'), '消息', 3000)
            client_id = bounded(body.get('clientId'), '发送标识', 80)
            existing = db.execute(SELECT_MESSAGE + 'WHERE m.user_id=? AND m.client_id=?', (user['id'], client_id)).fetchone()
            if existing:
                if existing['room_id'] != room or existing['body'] != content:
                    raise error(409, '发送标识已用于其他消息。')
                return {'message': message(existing, user)}
            now = int(time.time())
            recent = db.execute('SELECT COUNT(*) FROM messages WHERE user_id=? AND created>?', (user['id'], now - 60)).fetchone()[0]
            if recent >= 60:
                raise error(429, '发送太频繁，请稍后再试。')
            inserted = db.execute('INSERT INTO messages(room_id,user_id,body,created,client_id) VALUES (?,?,?,?,?)',
                                  (room, user['id'], content, now, client_id))
            db.execute('INSERT INTO message_events(room_id,message_id) VALUES (?,?)', (room, inserted.lastrowid))
            return {'message': message(db.execute(SELECT_MESSAGE + 'WHERE m.id=?', (inserted.lastrowid,)).fetchone(), user)}
    action = re.fullmatch(r'/v1/messages/(\d+)(/report)?', path)
    if action:
        old = db.execute('SELECT * FROM messages WHERE id=?', (int(action[1]),)).fetchone()
        if not old or old['recalled']:
            raise error(404, '消息不存在或已撤回。')
        if method == 'DELETE' and not action[2]:
            if old['user_id'] != user['id']:
                raise error(403, '只能撤回自己发送的消息。')
            db.execute('UPDATE messages SET recalled=1 WHERE id=?', (old['id'],))
            db.execute('INSERT INTO message_events(room_id,message_id) VALUES (?,?)', (old['room_id'], old['id']))
            return {'ok': True}
        if method == 'POST' and action[2]:
            reason = bounded(body.get('reason'), '举报原因', 300)
            db.execute('INSERT INTO message_reports VALUES (?,?,?) ON CONFLICT(message_id,user_id) DO UPDATE SET reason=excluded.reason',
                       (old['id'], user['id'], reason))
            return {'ok': True}
    return NOT_HANDLED
