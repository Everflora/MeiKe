#!/usr/bin/env python3
"""Read-only release gate; never creates identities or sends chat messages."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default='https://106.14.199.134/api/meike/')
    parser.add_argument('--origin', default='https://everflora.github.io')
    args = parser.parse_args()
    url = urlsplit(args.base)
    if (url.scheme != 'https' or not url.hostname or url.username or url.password
            or url.query or url.fragment or not url.path.endswith('/')):
        parser.error('API must be an HTTPS base URL ending in / without credentials/query/fragment')
    failures = []
    with tempfile.TemporaryDirectory(prefix='meike-api-check-') as folder:
        root = Path(folder)

        def request(method, path, origin=None, preflight=False):
            command = ['curl', '--silent', '--show-error', '--connect-timeout', '8',
                       '--max-time', '20', '--request', method,
                       '--dump-header', str(root / 'headers'),
                       '--output', str(root / 'body'), '--write-out', '%{http_code}']
            if origin:
                command += ['--header', 'Origin: ' + origin]
            if preflight:
                command += ['--header', 'Access-Control-Request-Method: POST',
                            '--header', 'Access-Control-Request-Headers: authorization,content-type']
            command.append(args.base + path)
            status = int(subprocess.check_output(command, text=True))
            block = (root / 'headers').read_text().strip().split('\n\n')[-1]
            headers = {k.lower(): v.strip() for line in block.splitlines()[1:]
                       if ':' in line for k, v in [line.split(':', 1)]}
            return status, headers, (root / 'body').read_text()

        def verify(label, condition):
            print(('PASS ' if condition else 'FAIL ') + label)
            if not condition:
                failures.append(label)

        status, _, body = request('GET', 'health')
        verify('Native health remains available', status == 200 and json.loads(body).get('ok') is True)
        status, headers, _ = request('OPTIONS', 'v1/profile', args.origin, True)
        verify('Browser preflight', status == 204 and headers.get('access-control-allow-origin') == args.origin
               and {'authorization', 'content-type'} <= {
                   x.strip().lower() for x in headers.get('access-control-allow-headers', '').split(',')})
        status, headers, _ = request('GET', 'health', args.origin)
        verify('Browser health', status == 200 and headers.get('access-control-allow-origin') == args.origin)
        status, headers, _ = request('GET', 'v1/profile', args.origin)
        verify('Authentication still required and readable by browser',
               status == 401 and headers.get('access-control-allow-origin') == args.origin)
        status, headers, _ = request('GET', 'health', 'https://example.invalid')
        verify('Unapproved origin rejected', status == 403 and 'access-control-allow-origin' not in headers)
    if failures:
        raise SystemExit('API is not ready for web release: ' + ', '.join(failures))


if __name__ == '__main__':
    main()
