"""MeiKe discussion API. Python 3.12+, SQLite, behind an HTTPS reverse proxy."""
import argparse
import hashlib
import json
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from matching import match_records
import chat
import chat_media
import chat_files
import teams


class ApiError(Exception):
    def __init__(self, status, message, code=None):
        self.status, self.message = status, message
        self.code = code


def bounded(value, name, limit, required=True):
    if not isinstance(value, str) or len(value.strip()) > limit or (required and not value.strip()):
        raise ApiError(400, f'{name}不能为空且最多 {limit} 字。')
    return value.strip()


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class Database:
    def __init__(self, file):
        self.file = str(file)
        Path(file).parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as db:
            db.executescript('''
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL, created INTEGER NOT NULL);
              CREATE TABLE IF NOT EXISTS rooms (
                id TEXT PRIMARY KEY, term TEXT NOT NULL, name TEXT NOT NULL,
                metadata TEXT NOT NULL);
              CREATE TABLE IF NOT EXISTS identities (
                identity TEXT PRIMARY KEY, room_id TEXT NOT NULL REFERENCES rooms(id));
              CREATE INDEX IF NOT EXISTS identities_room ON identities(room_id);
              CREATE TABLE IF NOT EXISTS academic_terms (
                code TEXT PRIMARY KEY, name TEXT NOT NULL);
              CREATE TABLE IF NOT EXISTS course_records (
                record_key TEXT PRIMARY KEY, term TEXT NOT NULL REFERENCES academic_terms(code),
                teaching_class_id TEXT NOT NULL, room_id TEXT NOT NULL REFERENCES rooms(id),
                data TEXT NOT NULL);
              CREATE INDEX IF NOT EXISTS course_records_room ON course_records(room_id);
              CREATE INDEX IF NOT EXISTS course_records_class ON course_records(term, teaching_class_id);
              CREATE TABLE IF NOT EXISTS posts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                room_id TEXT NOT NULL REFERENCES rooms(id),
                user_id TEXT NOT NULL REFERENCES users(id),
                parent_id INTEGER REFERENCES posts(id),
                title TEXT NOT NULL, body TEXT NOT NULL,
                created INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
              CREATE INDEX IF NOT EXISTS posts_room ON posts(room_id, parent_id, id);
              CREATE INDEX IF NOT EXISTS posts_user_time ON posts(user_id, created);
              CREATE TABLE IF NOT EXISTS reports (
                post_id INTEGER NOT NULL REFERENCES posts(id),
                user_id TEXT NOT NULL REFERENCES users(id), reason TEXT NOT NULL,
                PRIMARY KEY(post_id, user_id));
            ''')
            chat.initialize(db)
            teams.initialize(db)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.file, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            with db:
                yield db
        finally:
            db.close()

    @staticmethod
    def identity(term, values):
        if not isinstance(values, list) or not values:
            raise ApiError(400, '教学班标识无效。')
        if values[0] == 'COURSE_TEACHER_CLASS':
            if len(values) != 4:
                raise ApiError(400, '课程匹配标识无效。')
            bounded(values[1], '课程名称', 200)
            for members in values[2:]:
                if not isinstance(members, list) or not 0 < len(members) <= 1000:
                    raise ApiError(400, '老师或班级列表无效。')
                if any(not isinstance(v, str) or not v.strip() or len(v) > 160 for v in members):
                    raise ApiError(400, '老师或班级名称无效。')
                if members != sorted(set(members)):
                    raise ApiError(400, '老师和班级列表必须排序且无重复。')
            return json.dumps([bounded(term, '学期', 100), *values], ensure_ascii=False, separators=(',', ':'))
        if len(values) not in (2, 3):
            raise ApiError(400, '教学班标识无效。')
        if not all(isinstance(v, str) and 0 < len(v) <= 160 for v in values):
            raise ApiError(400, '教学班标识无效。')
        if (values[0], len(values)) not in [('JXBID', 2), ('JXBH', 3)]:
            raise ApiError(400, '教学班标识类型无效。')
        return json.dumps([bounded(term, '学期', 100), *values], ensure_ascii=False, separators=(',', ':'))

    def import_catalog(self, rooms, merges=None):
        if not isinstance(rooms, list):
            raise ValueError('目录应为分析工具输出的教学班数组。')
        # Catalog grouping follows the user's course-name/teacher/class rule.
        # Source teaching-class IDs remain aliases for personal schedule lookup.
        aliases = merges or []
        with self.connect() as db:
            for room in rooms:
                term = bounded(room['termCode'], '学期', 100)
                key = self.identity(term, room['identity'])
                room_id = digest(key)
                if room.get('roomKey', room_id) != room_id:
                    raise ValueError('目录讨论室标识与分组身份不一致。')
                existing = db.execute('SELECT room_id FROM identities WHERE identity=?', (key,)).fetchone()
                if existing:
                    room_id = existing['room_id']
                metadata = dict(room, roomKey=room_id)
                db.execute('INSERT INTO rooms VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, metadata=excluded.metadata',
                           (room_id, term, bounded(room['name'], '课程名称', 200), json.dumps(metadata, ensure_ascii=False)))
                db.execute('INSERT INTO identities VALUES (?,?) ON CONFLICT(identity) DO NOTHING', (key, room_id))
                db.execute('INSERT INTO academic_terms VALUES (?,?) ON CONFLICT(code) DO UPDATE SET name=excluded.name',
                           (term, room.get('termName', term)))
                for source in room.get('sourceIdentities', []):
                    source_key = self.identity(term, source)
                    old = db.execute('SELECT room_id FROM identities WHERE identity=?', (source_key,)).fetchone()
                    if old and old['room_id'] != room_id:
                        raise ValueError('原教学班标识已关联其他讨论室，需要明确迁移。')
                    db.execute('INSERT INTO identities VALUES (?,?) ON CONFLICT(identity) DO NOTHING', (source_key, room_id))
            for merge in aliases:
                bounded(merge.get('evidence'), '合并依据', 1000)
                target = self.identity(merge['termCode'], merge['target'])
                target_row = db.execute('SELECT room_id FROM identities WHERE identity=?', (target,)).fetchone()
                if not target_row:
                    raise ValueError('合并目标不在教学班目录中。')
                for source in merge['sources']:
                    key = self.identity(merge['termCode'], source)
                    old = db.execute('SELECT room_id FROM identities WHERE identity=?', (key,)).fetchone()
                    if not old:
                        raise ValueError('待合并教学班不在目录中。')
                    if old['room_id'] == target_row['room_id']:
                        continue
                    db.execute('UPDATE posts SET room_id=? WHERE room_id=?', (target_row['room_id'], old['room_id']))
                    db.execute('UPDATE identities SET room_id=? WHERE room_id=?', (target_row['room_id'], old['room_id']))
                    db.execute('UPDATE course_records SET room_id=? WHERE room_id=?', (target_row['room_id'], old['room_id']))
                    db.execute('UPDATE messages SET room_id=? WHERE room_id=?', (target_row['room_id'], old['room_id']))
                    db.execute('UPDATE message_events SET room_id=? WHERE room_id=?', (target_row['room_id'], old['room_id']))
                    db.execute('DELETE FROM rooms WHERE id=?', (old['room_id'],))

    def import_course_records(self, payload):
        term = bounded(payload.get('termCode'), '学期', 100)
        rows = payload.get('rows')
        if not isinstance(rows, list) or payload.get('totalCount') != len(rows):
            raise ValueError('原始课程行数与总数不一致。')
        with self.connect() as db:
            for row in rows:
                class_id = bounded(row.get('JXBID'), '教学班ID', 160)
                wid = bounded(row.get('WID'), '课程记录ID', 160)
                if row.get('XNXQDM') != term:
                    raise ValueError('原课程记录学期不符。')
                key = self.identity(term, ['JXBID', class_id])
                found = db.execute('SELECT room_id FROM identities WHERE identity=?', (key,)).fetchone()
                if not found:
                    raise ValueError('原课程记录未映射到讨论室。')
                record_key = json.dumps([term, wid], ensure_ascii=False, separators=(',', ':'))
                db.execute('INSERT INTO course_records VALUES (?,?,?,?,?) ON CONFLICT(record_key) DO UPDATE SET teaching_class_id=excluded.teaching_class_id, room_id=excluded.room_id, data=excluded.data',
                           (record_key, term, class_id, found['room_id'], json.dumps(row, ensure_ascii=False)))

    def route(self, method, path, query, body, token):
        with self.connect() as db:
            if method == 'GET' and path == '/health':
                return {'ok': True, 'version': 1}
            if method == 'POST' and path == '/v1/sessions':
                name = bounded(body.get('name'), '昵称', 24)
                value = secrets.token_urlsafe(32)
                user_id = secrets.token_hex(16)
                avatar = chat.avatar_bytes(body['avatar']) if 'avatar' in body else None
                version = hashlib.sha256(avatar).hexdigest() if avatar else ''
                db.execute('INSERT INTO users(id,token_hash,name,created,avatar,avatar_version) VALUES (?,?,?,?,?,?)',
                           (user_id, digest(value), name, int(time.time()), avatar, version))
                return {'token': value, 'user': {'id': user_id, 'name': name, 'avatarVersion': version}}
            user = db.execute('SELECT id,name,avatar_version FROM users WHERE token_hash=?', (digest(token),)).fetchone()
            if not user:
                raise ApiError(401, '讨论室登录已失效，请重新设置昵称。')
            result = teams.route(db, user, method, path, query, body, ApiError, bounded)
            if result is not teams.NOT_HANDLED:
                return result
            result = chat.route(db, user, method, path, query, body, ApiError, bounded)
            if result is not chat.NOT_HANDLED:
                return result
            if method == 'POST' and path == '/v1/rooms/match':
                term = bounded(body.get('termCode'), '学期', 100)
                name = bounded(body.get('name'), '课程名称', 200)
                teacher = bounded(body.get('teacher'), '教师', 500)
                records = db.execute('SELECT room_id,data FROM course_records WHERE term=?', (term,)).fetchall()
                found = match_records(name, teacher, body.get('meetings'),
                                      ((r['room_id'], json.loads(r['data'])) for r in records))
                if len(found) > 50:
                    raise ApiError(400, '匹配候选过多，请补全上课时间。')
                return {'rooms': [json.loads(db.execute('SELECT metadata FROM rooms WHERE id=?', (key,)).fetchone()[0])
                                  for key in found], 'matchFields': ['name', 'teacher', 'weeklyTimes']}
            if method == 'GET' and path == '/v1/terms':
                found = db.execute('SELECT term,metadata FROM rooms GROUP BY term ORDER BY term DESC').fetchall()
                return {'terms': [{'code': row['term'], 'name': json.loads(row['metadata']).get('termName', row['term'])} for row in found]}
            if method == 'GET' and path == '/v1/rooms':
                term = bounded(query.get('term', [''])[0], '学期', 100)
                search = query.get('q', [''])[0].strip()
                if len(search) > 100:
                    raise ApiError(400, '搜索内容过长。')
                # LIKE metacharacters are escaped so a search stays literal.
                search = search.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')
                found = db.execute("SELECT DISTINCT r.metadata FROM rooms r JOIN identities i ON i.room_id=r.id WHERE r.term=? AND r.name LIKE ? ESCAPE '\\' ORDER BY r.name LIMIT 100", (term, f'%{search}%')).fetchall()
                return {'rooms': [json.loads(row[0]) for row in found]}
            if method == 'POST' and path == '/v1/rooms/resolve':
                key = self.identity(body.get('termCode'), body.get('identity'))
                found = db.execute('SELECT r.metadata FROM identities i JOIN rooms r ON r.id=i.room_id WHERE i.identity=?', (key,)).fetchone()
                if not found:
                    raise ApiError(404, '此教学班尚未收录，请先核对全校课表目录。')
                return {'room': json.loads(found[0])}
            parts = path.strip('/').split('/')
            if len(parts) == 4 and parts[:2] == ['v1', 'rooms'] and parts[3] == 'posts':
                room_id = parts[2]
                if not db.execute('SELECT 1 FROM rooms WHERE id=?', (room_id,)).fetchone():
                    raise ApiError(404, '讨论室不存在。')
                if method == 'GET':
                    before = int(query.get('before', ['9223372036854775807'])[0])
                    parent = query.get('parent', [None])[0]
                    parent = int(parent) if parent is not None else None
                    rows = db.execute('''SELECT p.id,p.title,p.body,p.created,p.user_id,u.name,
                             (SELECT COUNT(*) FROM posts r WHERE r.parent_id=p.id AND r.deleted=0) replies
                             FROM posts p JOIN users u ON u.id=p.user_id
                             WHERE p.room_id=? AND p.parent_id IS ? AND p.deleted=0 AND p.id<?
                             ORDER BY p.id DESC LIMIT 30''', (room_id, parent, before)).fetchall()
                    return {'posts': [dict(row, mine=row['user_id'] == user['id']) for row in rows],
                            'next': rows[-1]['id'] if len(rows) == 30 else None}
                if method == 'POST':
                    parent = body.get('parent')
                    if parent is not None:
                        if not isinstance(parent, int) or not db.execute('SELECT 1 FROM posts WHERE id=? AND room_id=? AND parent_id IS NULL AND deleted=0', (parent, room_id)).fetchone():
                            raise ApiError(400, '回复目标不存在或属于其他讨论室。')
                    title = bounded(body.get('title', ''), '标题', 120, required=parent is None)
                    content = bounded(body.get('body'), '内容', 3000)
                    now = int(time.time())
                    recent = db.execute('SELECT COUNT(*) FROM posts WHERE user_id=? AND created>?', (user['id'], now - 60)).fetchone()[0]
                    if recent >= 5:
                        raise ApiError(429, '发送太频繁，请稍后再试。')
                    cursor = db.execute('INSERT INTO posts(room_id,user_id,parent_id,title,body,created) VALUES (?,?,?,?,?,?)', (room_id, user['id'], parent, title, content, now))
                    chat.mirror_post(db, db.execute('SELECT * FROM posts WHERE id=?', (cursor.lastrowid,)).fetchone())
                    return {'id': cursor.lastrowid}
            if len(parts) == 3 and parts[:2] == ['v1', 'posts'] and method == 'DELETE':
                post = db.execute('SELECT user_id FROM posts WHERE id=? AND deleted=0', (int(parts[2]),)).fetchone()
                if not post:
                    raise ApiError(404, '帖子不存在。')
                if post['user_id'] != user['id']:
                    raise ApiError(403, '只能删除自己发布的内容。')
                db.execute('UPDATE posts SET deleted=1 WHERE id=? OR parent_id=?', (int(parts[2]), int(parts[2])))
                chat.recall_legacy(db, int(parts[2]))
                return {'ok': True}
            if len(parts) == 4 and parts[:2] == ['v1', 'posts'] and parts[3] == 'report' and method == 'POST':
                post_id = int(parts[2])
                if not db.execute('SELECT 1 FROM posts WHERE id=? AND deleted=0', (post_id,)).fetchone():
                    raise ApiError(404, '帖子不存在。')
                reason = bounded(body.get('reason'), '反馈原因', 300)
                db.execute('INSERT INTO reports VALUES (?,?,?) ON CONFLICT(post_id,user_id) DO UPDATE SET reason=excluded.reason', (post_id, user['id'], reason))
                return {'ok': True}
            raise ApiError(404, '接口不存在。')


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, database):
        super().__init__(address, Handler)
        self.database = database
        self.session_attempts = {}


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, *_):
        pass  # Do not log bearer tokens, user content or query strings.

    def handle_api(self):
        status = 200
        try:
            parsed = urlsplit(self.path)
            body = {}
            if self.command in ('POST', 'PUT', 'DELETE'):
                length = int(self.headers.get('Content-Length', '0'))
                limit = (chat_files.MAX_REQUEST if self.command == 'POST' and re.fullmatch(r'/v1/rooms/[a-f0-9]{64}/messages', parsed.path)
                         else chat_media.MAX_REQUEST if self.command == 'POST' and parsed.path == '/v1/stickers'
                         else 150000 if parsed.path in ('/v1/profile', '/v1/sessions') else 20000)
                if length < 0 or length > limit:
                    self.close_connection = True
                    raise ApiError(413, '请求内容过大。')
                body = json.loads(self.rfile.read(length)) if length else {}
                if not isinstance(body, dict):
                    raise ApiError(400, '请求应为 JSON 对象。')
            if self.command == 'POST' and parsed.path == '/v1/sessions':
                # Reverse proxy must retain the real peer separately; clients
                # cannot select a rate-limit identity with a forwarded header.
                ip = self.client_address[0]
                if ip in ('127.0.0.1', '::1'):
                    ip = self.headers.get('X-Real-IP', ip)
                now = time.monotonic()
                times = [stamp for stamp in self.server.session_attempts.get(ip, []) if now - stamp < 3600]
                if len(times) >= 100:
                    raise ApiError(429, '创建身份太频繁，请稍后再试。')
                self.server.session_attempts[ip] = times + [now]
            auth = self.headers.get('Authorization', '')
            token = auth[7:] if auth.startswith('Bearer ') else ''
            result = self.server.database.route(self.command, parsed.path, parse_qs(parsed.query), body, token)
        except ApiError as error:
            status, result = error.status, {'error': error.message}
            if error.code:
                result['code'] = error.code
        except chat.AvatarError as error:
            status, result = 400, {'error': str(error), 'code': 'INVALID_AVATAR'}
        except chat_media.MediaError as error:
            status, result = 400, {'error': str(error), 'code': 'INVALID_MEDIA'}
        except (ValueError, TypeError, KeyError):
            status, result = 400, {'error': '请求参数无效。'}
        except Exception:
            status, result = 500, {'error': '服务暂时不可用，请稍后再试。'}
        binary = isinstance(result, bytes)
        encoded = result if binary else json.dumps(result, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', getattr(result, 'content_type', 'image/png') if binary else 'application/json; charset=utf-8')
        if binary and hasattr(result, 'content_disposition'):
            self.send_header('Content-Disposition', result.content_disposition)
        self.send_header('Content-Length', str(len(encoded)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(encoded)

    do_GET = do_POST = do_PUT = do_DELETE = handle_api


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', default='data/discussion.sqlite3')
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--catalog')
    parser.add_argument('--merges')
    parser.add_argument('--course-records')
    args = parser.parse_args()
    database = Database(args.db)
    if args.catalog:
        rooms = json.loads(Path(args.catalog).read_text(encoding='utf-8'))
        merges = json.loads(Path(args.merges).read_text(encoding='utf-8')) if args.merges else None
        database.import_catalog(rooms, merges)
        if args.course_records:
            database.import_course_records(json.loads(Path(args.course_records).read_text(encoding='utf-8')))
        print(f'已导入 {len(rooms)} 个教学班目录条目。')
        return
    print(f'MeiKe discussion API listening on {args.host}:{args.port}', flush=True)
    Server((args.host, args.port), database).serve_forever()


if __name__ == '__main__':
    main()
