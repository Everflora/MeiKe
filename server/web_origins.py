"""Explicit browser origins. Native clients without Origin are unchanged."""
from urllib.parse import urlsplit


def parse_origins(value):
    origins = set()
    for item in value.split(','):
        origin = item.strip()
        if not origin:
            continue
        url = urlsplit(origin)
        local = url.hostname in ('localhost', '127.0.0.1', '::1')
        if (url.scheme not in (('http', 'https') if local else ('https',))
                or not url.hostname or url.username or url.password
                or url.path or url.query or url.fragment or '*' in origin):
            raise ValueError('MEIKE_WEB_ORIGINS must contain exact HTTPS origins without paths or wildcards')
        origins.add(origin)
    return frozenset(origins)
