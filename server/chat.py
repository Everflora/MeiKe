"""Authenticated chat, editable profiles and avatars stored in SQLite."""
import base64
import binascii
import hashlib
import json
import re
import struct
import time
import zlib
import chat_media
import chat_stickers
import chat_files


NOT_HANDLED = object()


class AvatarError(ValueError):
    """Safe, user-facing validation error for avatar uploads."""


def avatar_bytes(value):
    if value is None:
        return None
    if not isinstance(value, str) or len(value) > 131072:
        raise AvatarError('头像文件过大。')
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        raise AvatarError('头像编码无效。') from None
    if len(data) > 98304 or not data.startswith(b'\x89PNG\r\n\x1a\n'):
        raise AvatarError('请选择有效的头像图片。')
    position, compressed, header, ended = 8, b'', None, False
    while position + 12 <= len(data):
        size = struct.unpack('>I', data[position:position + 4])[0]
        kind = data[position + 4:position + 8]
        end = position + 12 + size
        if end > len(data):
            raise AvatarError('头像图片不完整。')
        part = data[position + 8:position + 8 + size]
        checksum = struct.unpack('>I', data[end - 4:end])[0]
        if zlib.crc32(kind + part) & 0xffffffff != checksum:
            raise AvatarError('头像图片校验失败。')
        if kind == b'IHDR':
            if header is not None or position != 8 or size != 13:
                raise AvatarError('头像图片头无效。')
            header = struct.unpack('>IIBBBBB', part)
        elif kind == b'IDAT':
            compressed += part
        elif kind == b'IEND':
            if size != 0 or end != len(data):
                raise AvatarError('头像图片结尾无效。')
            ended = True
        position = end
    if (not ended or not header or header[:3] != (128, 128, 8)
            or header[3] not in (2, 6) or header[4:] != (0, 0, 0)):
        raise AvatarError('头像需要由应用转换成 128×128 PNG 图片。')
    try:
        decoder = zlib.decompressobj()
        expected = 128 * (128 * (4 if header[3] == 6 else 3) + 1)
        pixels = decoder.decompress(compressed, expected + 1)
        if len(pixels) != expected or not decoder.eof or decoder.unused_data:
            raise AvatarError('头像像素数据无效。')
    except zlib.error:
        raise AvatarError('头像像素数据无效。') from None
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
    columns = {row['name'] for row in db.execute('PRAGMA table_info(messages)')}
    for name, definition in [('kind', "TEXT NOT NULL DEFAULT 'text'"),
                             ('media_width', 'INTEGER'), ('media_height', 'INTEGER'),
                             ('media_hash', "TEXT NOT NULL DEFAULT ''"),
                             ('file_name', 'TEXT'), ('file_size', 'INTEGER')]:
        if name not in columns:
            db.execute(f'ALTER TABLE messages ADD COLUMN {name} {definition}')
    db.execute('''CREATE TABLE IF NOT EXISTS message_media (
        message_id INTEGER PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
        data BLOB NOT NULL, mime TEXT NOT NULL)''')
    chat_stickers.initialize(db)
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
            'mine': row['user_id'] == user['id'], 'clientId': row['client_id'],
            'kind': row['kind'],
            'media': None if row['recalled'] or row['kind'] not in ('image', 'sticker') else {
                'width': row['media_width'], 'height': row['media_height']},
            'file': {'name': row['file_name'], 'size': row['file_size']}
                if not row['recalled'] and row['kind'] == 'file' else None}


SELECT_MESSAGE = 'SELECT m.*,u.name,u.avatar_version FROM messages m JOIN users u ON u.id=m.user_id '


def route(db, user, method, path, query, body, error, bounded, events=None):
    saved = chat_stickers.route(db, user, method, path, body, error)
    if saved is not chat_stickers.NOT_HANDLED:
        return saved
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
    media_match = re.fullmatch(r'/v1/messages/(\d+)/media', path)
    if method == 'GET' and media_match:
        row = db.execute('''SELECT a.data,a.mime,m.kind,m.file_name FROM message_media a
            JOIN messages m ON m.id=a.message_id WHERE m.id=? AND m.recalled=0''',
                         (int(media_match[1]),)).fetchone()
        if not row:
            raise error(404, '附件不存在或消息已撤回。')
        return (chat_files.FileBytes(row['data'], row['file_name']) if row['kind'] == 'file'
                else chat_media.MediaBytes(row['data'], row['mime']))
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
                    generation = events.snapshot(room) if events else None
                    changes = db.execute('''SELECT e.id AS event_id,m.*,u.name,u.avatar_version
                        FROM message_events e JOIN messages m ON m.id=e.message_id
                        JOIN users u ON u.id=m.user_id WHERE e.room_id=? AND e.id>? ORDER BY e.id LIMIT 100''', (room, after)).fetchall()
                    if changes or time.monotonic() >= deadline:
                        return {'messages': [message(row, user) for row in changes],
                                'cursor': changes[-1]['event_id'] if changes else after, 'before': None}
                    remaining = max(0, deadline - time.monotonic())
                    if events:
                        # Periodic cursor checks heal missed Redis notifications.
                        events.wait(room, generation, min(4, remaining))
                    else:
                        time.sleep(min(.25, remaining))
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
            kind = body.get('kind', 'text')
            if kind == 'file':
                raise error(400, '文件上传功能已关闭。', 'FILE_UPLOAD_DISABLED')
            if kind not in ('text', 'image', 'sticker'):
                raise error(400, '不支持的消息类型。')
            media, width, height, mime, media_hash = None, None, None, None, ''
            if kind != 'text':
                if 'stickerId' in body:
                    if kind != 'sticker' or 'media' in body or not isinstance(body['stickerId'], str):
                        raise error(400, '表情包发送参数无效。')
                    saved = db.execute('SELECT data,width,height,mime FROM saved_stickers WHERE id=? AND user_id=?', (body['stickerId'], user['id'])).fetchone()
                    if not saved:
                        raise error(404, '表情包不存在或已移除。')
                    media, width, height, mime = saved
                else:
                    media, width, height, mime = chat_media.parse(body.get('media'))
                media_hash = hashlib.sha256(media).hexdigest()
                content = '[表情包]' if kind == 'sticker' else '[图片]'
            else:
                if 'media' in body or 'stickerId' in body:
                    raise error(400, '文字消息不能包含图片。')
                content = bounded(body.get('body'), '消息', 3000)
            client_id = bounded(body.get('clientId'), '发送标识', 80)
            db.execute('BEGIN IMMEDIATE')
            existing = db.execute(SELECT_MESSAGE + 'WHERE m.user_id=? AND m.client_id=?', (user['id'], client_id)).fetchone()
            if existing:
                if existing['room_id'] != room or existing['body'] != content or existing['kind'] != kind or existing['media_hash'] != media_hash:
                    raise error(409, '发送标识已用于其他消息。')
                return {'message': message(existing, user)}
            now = int(time.time())
            recent = db.execute('SELECT COUNT(*) FROM messages WHERE user_id=? AND created>?', (user['id'], now - 60)).fetchone()[0]
            if recent >= 60:
                raise error(429, '发送太频繁，请稍后再试。')
            if media:
                recent_media = db.execute("SELECT COUNT(*) FROM messages WHERE user_id=? AND kind!='text' AND created>?", (user['id'], now - 60)).fetchone()[0]
                used = db.execute('''SELECT COALESCE(SUM(length(a.data)),0) FROM message_media a
                    JOIN messages m ON m.id=a.message_id WHERE m.user_id=? AND m.created>?''', (user['id'], now - 86400)).fetchone()[0]
                if recent_media >= 10 or used + len(media) > 100 * 1024 * 1024:
                    raise error(429, '附件发送过多，请稍后再试。')
            inserted = db.execute('''INSERT INTO messages(room_id,user_id,body,created,client_id,kind,media_width,media_height,media_hash,file_name,file_size)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)''', (room, user['id'], content, now, client_id, kind, width, height, media_hash, None, None))
            if media:
                db.execute('INSERT INTO message_media VALUES (?,?,?)', (inserted.lastrowid, media, mime))
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
            db.execute('DELETE FROM message_media WHERE message_id=?', (old['id'],))
            db.execute('INSERT INTO message_events(room_id,message_id) VALUES (?,?)', (old['room_id'], old['id']))
            return {'ok': True}
        if method == 'POST' and action[2]:
            reason = bounded(body.get('reason'), '举报原因', 300)
            db.execute('INSERT INTO message_reports VALUES (?,?,?) ON CONFLICT(message_id,user_id) DO UPDATE SET reason=excluded.reason',
                       (old['id'], user['id'], reason))
            return {'ok': True}
    return NOT_HANDLED
