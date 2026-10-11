"""Bounded PNG/GIF attachments. No filesystem paths or client MIME trust."""
import base64
import binascii
import struct
import zlib

MAX_BYTES = 3 * 1024 * 1024
MAX_REQUEST = 4 * 1024 * 1024 + 20000


class MediaError(ValueError):
    pass


class MediaBytes(bytes):
    def __new__(cls, data, mime):
        result = super().__new__(cls, data)
        result.content_type = mime
        return result


def dimensions(width, height, limit=768):
    if not 1 <= width <= limit or not 1 <= height <= limit:
        raise MediaError(f'图片宽高不能超过 {limit} 像素，请选择较小的图片。')


def png_info(data):
    pos, header, compressed, ended = 8, None, bytearray(), False
    while pos + 12 <= len(data):
        size = struct.unpack_from('>I', data, pos)[0]
        kind = data[pos + 4:pos + 8]
        end = pos + size + 12
        if end > len(data):
            raise MediaError('图片数据不完整。')
        part = data[pos + 8:end - 4]
        if zlib.crc32(kind + part) & 0xffffffff != struct.unpack_from('>I', data, end - 4)[0]:
            raise MediaError('图片校验失败。')
        if kind == b'IHDR':
            if pos != 8 or size != 13 or header:
                raise MediaError('图片头无效。')
            header = struct.unpack('>IIBBBBB', part)
        elif kind == b'IDAT':
            compressed.extend(part)
        elif kind == b'IEND':
            ended = size == 0 and end == len(data)
        else:
            # Only accept the simple PNG format emitted by the application.
            raise MediaError('请使用应用重新处理图片。')
        pos = end
    if not header or not ended or header[2] != 8 or header[3] not in (2, 6) or header[4:] != (0, 0, 0):
        raise MediaError('请使用应用重新处理图片。')
    width, height = header[:2]
    dimensions(width, height)
    stride = width * (4 if header[3] == 6 else 3) + 1
    try:
        decoder = zlib.decompressobj()
        pixels = decoder.decompress(compressed, height * stride + 1)
    except zlib.error:
        raise MediaError('图片像素数据无效。') from None
    if len(pixels) != height * stride or not decoder.eof or decoder.unused_data or any(pixels[row * stride] > 4 for row in range(height)):
        raise MediaError('图片像素数据无效。')
    return width, height, 'image/png'


def gif_info(data):
    if len(data) < 14:
        raise MediaError('GIF 数据不完整。')
    width, height = struct.unpack_from('<HH', data, 6)
    dimensions(width, height, 512)
    pos, frames = 13, 0
    global_palette = bool(data[10] & 128)
    if global_palette:
        pos += 3 * (1 << ((data[10] & 7) + 1))

    def subblocks(offset):
        total = 0
        while offset < len(data):
            size = data[offset]
            offset += 1
            if not size:
                return offset, total
            total += size
            offset += size
        raise MediaError('GIF 数据不完整。')

    while pos < len(data):
        marker = data[pos]
        pos += 1
        if marker == 0x3b:
            if pos != len(data) or not frames:
                break
            return width, height, 'image/gif'
        if marker == 0x21:
            if pos >= len(data) or data[pos] not in (0xf9, 0xff, 0xfe):
                raise MediaError('GIF 扩展格式不支持。')
            label = data[pos]
            pos += 1
            if label == 0xf9 and (pos + 6 > len(data) or data[pos] != 4 or data[pos + 5] != 0):
                raise MediaError('GIF 控制数据无效。')
            if label == 0xff and (pos >= len(data) or data[pos] != 11):
                raise MediaError('GIF 扩展数据无效。')
            pos, _ = subblocks(pos)
        elif marker == 0x2c:
            if pos + 9 >= len(data):
                break
            left, top, fw, fh, packed = struct.unpack_from('<HHHHB', data, pos)
            if not fw or not fh or left + fw > width or top + fh > height:
                raise MediaError('GIF 帧尺寸无效。')
            frames += 1
            if frames > 200 or frames * width * height > 32 * 1024 * 1024:
                raise MediaError('GIF 动画过长，请选择较短的表情包。')
            pos += 9
            if packed & 128:
                pos += 3 * (1 << ((packed & 7) + 1))
            elif not global_palette:
                raise MediaError('GIF 缺少颜色表。')
            if pos >= len(data) or not 2 <= data[pos] <= 8:
                raise MediaError('GIF 图片数据无效。')
            pos, size = subblocks(pos + 1)
            if not size:
                raise MediaError('GIF 图片数据为空。')
        else:
            break
    raise MediaError('GIF 数据不完整或格式无效。')


def parse(value):
    if not isinstance(value, str) or len(value) > MAX_BYTES * 4 // 3:
        raise MediaError('发送的图片不能超过 3 MB。')
    try:
        data = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        raise MediaError('图片编码无效。') from None
    if not data or len(data) > MAX_BYTES:
        raise MediaError('发送的图片不能超过 3 MB。')
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        width, height, mime = png_info(data)
    elif data.startswith((b'GIF87a', b'GIF89a')):
        width, height, mime = gif_info(data)
    else:
        raise MediaError('请选择有效的图片或 GIF 表情包。')
    return data, width, height, mime
