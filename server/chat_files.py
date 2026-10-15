"""Authenticated historical file downloads; new file uploads are disabled."""
from urllib.parse import quote


class FileBytes(bytes):
    def __new__(cls, data, name):
        result = super().__new__(cls, data)
        result.content_type = 'application/octet-stream'
        result.content_disposition = "attachment; filename=download; filename*=UTF-8''" + quote(name, safe='')
        return result
