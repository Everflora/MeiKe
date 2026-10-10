"""Read-only check of imported rooms and every source-class mapping."""
import argparse
import json
import sqlite3
from pathlib import Path
from app import Database


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--catalog', required=True)
    parser.add_argument('--course-records', required=True)
    args = parser.parse_args()
    rooms = json.loads(Path(args.catalog).read_text(encoding='utf-8'))
    rows = json.loads(Path(args.course_records).read_text(encoding='utf-8'))['rows']
    with sqlite3.connect(Path(args.db).resolve().as_uri() + '?mode=ro', uri=True) as db:
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        counts = {table: db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0]
                  for table in ('academic_terms', 'rooms', 'identities', 'course_records', 'users', 'posts', 'reports', 'messages', 'message_events', 'message_reports')}
        assert counts['rooms'] == len(rooms)
        assert counts['course_records'] == len(rows)
        for room in rooms:
            for source in room['sourceIdentities']:
                key = Database.identity(room['termCode'], source)
                result = db.execute('SELECT room_id FROM identities WHERE identity=?', (key,)).fetchone()
                assert result and result[0] == room['roomKey']
        for row in rows:
            key = Database.identity(row['XNXQDM'], ['JXBID', row['JXBID']])
            result = db.execute('SELECT r.room_id,r.data FROM course_records r JOIN identities i ON i.identity=? WHERE r.teaching_class_id=? AND r.term=?',
                                (key, row['JXBID'], row['XNXQDM'])).fetchone()
            expected = db.execute('SELECT room_id FROM identities WHERE identity=?', (key,)).fetchone()
            assert result and result[0] == expected[0] and json.loads(result[1]) == row
        missing_legacy = db.execute('''SELECT COUNT(*) FROM posts p WHERE NOT EXISTS
            (SELECT 1 FROM messages m WHERE m.user_id=p.user_id AND m.client_id='legacy-post:' || p.id)''').fetchone()[0]
        assert missing_legacy == 0
        avatar_users = db.execute('SELECT COUNT(*) FROM users WHERE avatar IS NOT NULL AND avatar_version != ? ', ('',)).fetchone()[0]
        print(json.dumps({'integrity': 'ok', 'foreignKeys': 'ok', 'counts': counts,
                          'verifiedSourceMappings': len(rows), 'legacyMigration': 'ok',
                          'profilesWithAvatar': avatar_users}, ensure_ascii=False))


if __name__ == '__main__':
    main()
