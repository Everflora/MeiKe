"""Opaque chat files: bounded bytes, display-only filenames, never executed."""
import base64
import binascii
import re
import unicodedata
from urllib.parse import quote

MAX_BYTES = 10 * 1024 * 1024
MAX_REQUEST = ((MAX_BYTES + 2) // 3) * 4 + 20000


def parse(body, error):
    name, encoded = body.get('fileName'), body.get('media')
    if not isinstance(name, str):
        raise error(400, '文件名无效。')
    name = unicodedata.normalize('NFC', name.strip())
    if (not name or name in ('.', '..') or len(name.encode('utf-8')) > 240
            or re.search(r'[/\\\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]', name)):
        raise error(400, '文件名无效，请重命名后重试。')
    if not isinstance(encoded, str) or len(encoded) > ((MAX_BYTES + 2) // 3) * 4:
        raise error(413, '文件不能超过 10 MB。')
    try:
        data = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise error(400, '文件内容无效。') from None
    if not data or len(data) > MAX_BYTES:
        raise error(413, '请选择非空且不超过 10 MB 的文件。')
    if 'stickerId' in body:
        raise error(400, '文件消息参数无效。')
    return data, name


class FileBytes(bytes):
    def __new__(cls, data, name):
        result = super().__new__(cls, data)
        result.content_type = 'application/octet-stream'
        result.content_disposition = "attachment; filename=download; filename*=UTF-8''" + quote(name, safe='')
        return result
