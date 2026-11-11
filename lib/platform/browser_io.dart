// The subset of native IO used by MeiKe: transactional browser files and fetch.
// No in-memory fallback: failed persistence must be reported to the user.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;
import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';
import 'package:web/web.dart' as web;

class IOException implements Exception {
  const IOException([this.message = '浏览器网络请求失败']);
  final String message;
  @override
  String toString() => message;
}

class FileSystemException extends IOException {
  const FileSystemException([super.message = '浏览器无法保存数据，请导出备份。']);
}

Future<web.IDBDatabase> _openDatabase() async {
  final done = Completer<web.IDBDatabase>();
  final scope = Uri.parse(web.document.baseURI).path;
  final request = web.window.indexedDB.open('meike:$scope', 1);
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    db.createObjectStore('files');
  }).toJS;
  request.onsuccess = ((web.Event _) {
    if (!done.isCompleted) done.complete(request.result as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event _) {
    if (!done.isCompleted) done.completeError(const FileSystemException());
  }).toJS;
  request.onblocked = ((web.Event _) {
    if (!done.isCompleted) {
      done.completeError(const FileSystemException('请关闭其他梅课页面后重试。'));
    }
  }).toJS;
  return done.future;
}

Future<T> _transaction<T>(
  bool write,
  void Function(web.IDBObjectStore store, void Function(T value) result) action,
) async {
  web.IDBDatabase? db;
  try {
    db = await _openDatabase();
    final transaction = db.transaction(
      'files'.toJS,
      write ? 'readwrite' : 'readonly',
    );
    final done = Completer<T>();
    T? value;
    transaction.oncomplete = ((web.Event _) {
      if (!done.isCompleted) done.complete(value as T);
    }).toJS;
    void fail(web.Event _) {
      if (!done.isCompleted) done.completeError(const FileSystemException());
    }

    transaction.onerror = fail.toJS;
    transaction.onabort = fail.toJS;
    action(transaction.objectStore('files'), (v) => value = v);
    return await done.future;
  } on FileSystemException {
    rethrow;
  } catch (_) {
    throw const FileSystemException();
  } finally {
    db?.close();
  }
}

class Directory {
  const Directory(this.path);
  final String path;
  Future<Directory> create({bool recursive = false}) async => this;
}

class File {
  const File(this.path);
  final String path;
  Directory get parent => Directory(path.substring(0, path.lastIndexOf('/')));
  Future<String?> _read() => _transaction<String?>(false, (store, result) {
    final request = store.get(path.toJS);
    request.onsuccess = ((web.Event _) {
      final value = request.result;
      result(value.isUndefinedOrNull ? null : (value as JSString).toDart);
    }).toJS;
  });
  Future<bool> exists() async => await _read() != null;
  Future<Uint8List> readAsBytes() async {
    final value = await _read();
    if (value == null) throw const FileSystemException('未找到本地记录。');
    return base64Decode(value);
  }

  Future<String> readAsString() async => utf8.decode(await readAsBytes());
  Future<int> length() async => (await readAsBytes()).length;
  Future<File> writeAsBytes(List<int> bytes, {bool flush = false}) async {
    final encoded = base64Encode(bytes);
    await _transaction<bool>(true, (store, result) {
      store.put(encoded.toJS, path.toJS);
      result(true);
    });
    return this;
  }

  Future<File> writeAsString(String text, {bool flush = false}) =>
      writeAsBytes(utf8.encode(text), flush: flush);
  Future<File> copy(String destination) async =>
      File(destination).writeAsBytes(await readAsBytes());
  Future<File> rename(String destination) async {
    // Reading the temporary record and replacing the saved record are one
    // transaction. Quota errors/aborts leave the previous destination intact.
    final moved = await _transaction<bool>(true, (store, result) {
      final request = store.get(path.toJS);
      request.onsuccess = ((web.Event _) {
        if (request.result.isUndefinedOrNull) {
          result(false);
        } else {
          store.put(request.result, destination.toJS);
          if (destination != path) store.delete(path.toJS);
          result(true);
        }
      }).toJS;
    });
    if (!moved) throw const FileSystemException('未找到要保存的临时记录。');
    return File(destination);
  }

  Future<File> delete() async {
    await _transaction<bool>(true, (store, result) {
      store.delete(path.toJS);
      result(true);
    });
    return this;
  }
}

class ContentType {
  const ContentType(this.value);
  final String value;
  static const json = ContentType('application/json; charset=utf-8');
}

class HttpHeaders {
  HttpHeaders([Map<String, String>? values]) : values = values ?? {};
  final Map<String, String> values;
  static const authorizationHeader = 'authorization';
  static const acceptHeader = 'accept';
  static const locationHeader = 'location';
  void set(String key, Object value) => values[key.toLowerCase()] = '$value';
  String? value(String key) => values[key.toLowerCase()];
  set contentType(ContentType type) => set('content-type', type.value);
}

class HttpClient {
  final BrowserClient _client = BrowserClient();
  Duration? connectionTimeout;
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      HttpClientRequest(_client, method, url);
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  void close({bool force = false}) => _client.close();
}

class HttpClientRequest {
  HttpClientRequest(this.client, this.method, this.url);
  final BrowserClient client;
  final String method;
  final Uri url;
  final headers = HttpHeaders();
  final _body = BytesBuilder(copy: false);
  bool followRedirects = false;
  int contentLength = 0;
  void add(List<int> bytes) => _body.add(bytes);
  Future<HttpClientResponse> close() async {
    try {
      final request = http.Request(method, url)
        ..followRedirects = followRedirects
        ..headers.addAll(headers.values)
        ..bodyBytes = _body.takeBytes();
      return HttpClientResponse(await client.send(request));
    } on http.ClientException {
      throw const IOException();
    }
  }
}

class HttpClientResponse extends StreamView<List<int>> {
  HttpClientResponse(http.StreamedResponse response)
    : statusCode = response.statusCode,
      headers = HttpHeaders(response.headers),
      super(
        response.stream.handleError((Object _) => throw const IOException()),
      );
  final int statusCode;
  final HttpHeaders headers;
}

class ZLibEncoder {
  List<int> convert(List<int> bytes) => archive.ZLibEncoder().encode(bytes);
}
