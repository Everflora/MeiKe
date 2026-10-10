"""Add only the MeiKe API location to the existing verified HTTPS site."""
import shutil
from datetime import datetime, timezone
from pathlib import Path

target = Path('/etc/nginx/sites-enabled/project-http').resolve(strict=True)
if target.parent not in (Path('/etc/nginx/sites-available'), Path('/etc/nginx/sites-enabled')):
    raise RuntimeError('站点配置路径不符，停止。')
source = target.read_text()
anchor = '    location ^~ /api/delivery/ {'
route = '''    location ^~ /api/meike/ {
        proxy_pass http://127.0.0.1:8765/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Connection "";
        client_max_body_size 150k;
        proxy_read_timeout 30s;
        access_log off;
    }

'''
if 'location ^~ /api/meike/' not in source:
    if source.count(anchor) != 1:
        raise RuntimeError('原 HTTPS 路由不符，停止。')
    backup = Path('/home/admin/meike-discussion/backups') / ('nginx-before-meike-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '.conf')
    shutil.copy2(target, backup)
    backup.chmod(0o600)
    target.write_text(source.replace(anchor, route + anchor, 1))
    print('Added MeiKe location; original site configuration backed up.')
else:
    start = source.index('    location ^~ /api/meike/ {')
    end = source.index('\n    }', start) + len('\n    }')
    existing = source[start:end]
    if existing.count('client_max_body_size 20k;') == 1:
        backup = Path('/home/admin/meike-discussion/backups') / ('nginx-before-chat-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '.conf')
        shutil.copy2(target, backup)
        backup.chmod(0o600)
        target.write_text(source[:start] + existing.replace('client_max_body_size 20k;', 'client_max_body_size 150k;', 1) + source[end:])
        print('Updated only MeiKe avatar upload limit; original configuration backed up.')
    elif existing.count('client_max_body_size 150k;') == 1:
        print('MeiKe location already supports avatars; configuration unchanged.')
    else:
        raise RuntimeError('MeiKe 上传配置不符，停止。')
