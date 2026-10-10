"""Create an SQLite online backup without copying WAL files."""
import argparse
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--db', required=True)
    parser.add_argument('--output', default='backups')
    args = parser.parse_args()
    folder = Path(args.output)
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / ('discussion-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.sqlite3')
    with closing(sqlite3.connect(Path(args.db).resolve().as_uri() + '?mode=ro', uri=True)) as source:
        with closing(sqlite3.connect(target)) as backup:
            source.backup(backup)
            if backup.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise RuntimeError('数据库备份完整性检查失败。')
    target.chmod(0o600)
    print(target)


if __name__ == '__main__':
    main()
