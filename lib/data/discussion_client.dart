import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/schedule.dart';
import 'chat_file.dart';

Json discussionMatchRequest(Course course, String termCode) {
  if (course.name.trim().isEmpty || course.teacher.trim().isEmpty) {
    throw const FormatException('请先补全课程名称和教师。');
  }
  if (course.meetings.isEmpty) {
    throw const FormatException('请先为这门课添加每周上课时间。');
  }
  return {
    'termCode': termCode,
    'name': course.name.trim(),
    'teacher': course.teacher.trim(),
    'meetings': [
      for (final meeting in course.meetings)
        {
          'weekday': meeting.weekday,
          'startPeriod': meeting.startPeriod,
          'endPeriod': meeting.endPeriod,
          'weeks': [
            for (var week = meeting.startWeek; week <= meeting.endWeek; week++)
              if (meeting.occurs(week)) week,
          ],
        },
    ],
  };
}

class DiscussionRoom {
  DiscussionRoom(this.json);
  final Json json;
  String get id => json['roomKey'] as String;
  String get name => json['name'] as String;
  String get teacher => (json['teachers'] as List).join('、');
  String get classes => (json['attendingClassNames'] as List).isEmpty
      ? '学校未提供上课班级'
      : (json['attendingClassNames'] as List).join('、');
  String get schedule => (json['arrangements'] as List)
      .map((item) => (item as Json)['YPSJDD'] as String? ?? '')
      .where((value) => value.isNotEmpty)
      .join('\n');
}

class DiscussionClient {
  DiscussionClient({
    required this.sessionFile,
    HttpClient? transport,
    Uri? base,
  }) : _http = transport ?? HttpClient(),
       base =
           base ??
           Uri.parse(
             const String.fromEnvironment(
               'DISCUSSION_API',
               defaultValue: 'https://106.14.199.134/api/meike/',
             ),
           ) {
    if (this.base.scheme != 'https') {
      throw const FormatException('讨论室服务器需要 HTTPS。');
    }
    _http.connectionTimeout = const Duration(seconds: 12);
  }
  final File sessionFile;
  final HttpClient _http;
  final Uri base;
  String _token = '';
  String nickname = '';
  String userId = '', avatarVersion = '';
  bool get signedIn => _token.isNotEmpty;

  Future<void> loadSession() async {
    if (!await sessionFile.exists()) return;
    try {
      if (await sessionFile.length() > 4096) return;
      final data = jsonDecode(await sessionFile.readAsString()) as Json;
      _token = data['token'] as String;
      nickname = data['nickname'] as String;
      userId = data['userId'] as String? ?? '';
      avatarVersion = data['avatarVersion'] as String? ?? '';
    } on FormatException {
      _token = '';
    } on TypeError {
      _token = '';
    }
  }

  Future<void> signIn(String name, {Uint8List? avatar}) async {
    final data = await request(
      'POST',
      'v1/sessions',
      body: {
        'name': name.trim(),
        if (avatar != null) 'avatar': base64Encode(avatar),
      },
    );
    final token = data['token'] as String;
    final user = data['user'] as Json;
    _token = token;
    await _storeProfile(user);
  }

  Future<void> _storeProfile(Json user) async {
    nickname = user['name'] as String;
    userId = user['id'] as String;
    avatarVersion = user['avatarVersion'] as String? ?? '';
    await sessionFile.parent.create(recursive: true);
    final temp = File('${sessionFile.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'token': _token,
        'nickname': nickname,
        'userId': userId,
        'avatarVersion': avatarVersion,
      }),
      flush: true,
    );
    await temp.rename(sessionFile.path);
  }

  Future<void> refreshProfile() async =>
      _storeProfile(await request('GET', 'v1/profile'));

  Future<void> saveProfile(
    String name, {
    Uint8List? avatar,
    bool removeAvatar = false,
  }) async {
    await _storeProfile(
      await request(
        'POST',
        'v1/profile',
        body: {
          'name': name.trim(),
          if (removeAvatar)
            'avatar': null
          else if (avatar != null)
            'avatar': base64Encode(avatar),
        },
      ),
    );
  }

  Map<String, String> get imageHeaders => {'Authorization': 'Bearer $_token'};
  String avatarUrl(String id, String version) =>
      base.resolve('v1/users/$id/avatar?version=$version').toString();
  String messageImageUrl(int id) =>
      base.resolve('v1/messages/$id/media').toString();
  String stickerImageUrl(String id) =>
      base.resolve('v1/stickers/$id/media').toString();
  Future<List<Json>> savedStickers() async =>
      ((await request('GET', 'v1/stickers'))['stickers'] as List).cast<Json>();
  Future<Json> addSticker({Uint8List? bytes, int? messageId}) async =>
      (await request(
            'POST',
            'v1/stickers',
            body: {
              if (bytes != null) 'media': base64Encode(bytes),
              'messageId': ?messageId,
            },
          ))['sticker']
          as Json;
  Future<void> removeSticker(String id) async {
    await request('DELETE', 'v1/stickers/$id');
  }

  Future<Json> sendSticker(
    String room,
    String stickerId,
    String clientId,
  ) async =>
      (await request(
            'POST',
            'v1/rooms/$room/messages',
            body: {
              'kind': 'sticker',
              'stickerId': stickerId,
              'clientId': clientId,
            },
          ))['message']
          as Json;

  Future<Json> sendImage(
    String room,
    Uint8List bytes,
    String clientId, {
    bool sticker = false,
  }) async =>
      (await request(
            'POST',
            'v1/rooms/$room/messages',
            body: {
              'clientId': clientId,
              'kind': sticker ? 'sticker' : 'image',
              'media': base64Encode(bytes),
            },
          ))['message']
          as Json;

  Future<Json> sendFile(
    String room,
    String name,
    Uint8List bytes,
    String clientId,
  ) async {
    if (bytes.isEmpty || bytes.length > maxChatFileBytes) {
      throw const FormatException('请选择非空且不超过 10 MB 的文件。');
    }
    try {
      return (await request(
            'POST',
            'v1/rooms/$room/messages',
            body: {
              'kind': 'file',
              'fileName': chatFileName(name),
              'media': base64Encode(bytes),
              'clientId': clientId,
            },
          ))['message']
          as Json;
    } on FormatException catch (e) {
      if (e.message == '不支持的消息类型。') {
        throw const FormatException('文件服务暂未启用，请稍后再试。');
      }
      rethrow;
    }
  }

  Future<Uint8List> downloadFile(int id, int expectedSize) async {
    if (expectedSize < 1 || expectedSize > maxChatFileBytes) {
      throw const FormatException('文件大小无效。');
    }
    try {
      final req = await _http
          .getUrl(base.resolve('v1/messages/$id/media'))
          .timeout(const Duration(seconds: 15));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      final response = await req.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        if (response.statusCode == 401) _token = '';
        await response.timeout(const Duration(seconds: 15)).drain<void>();
        throw FormatException(
          response.statusCode == 404 ? '文件不存在或消息已撤回。' : '文件下载失败，请重试。',
        );
      }
      final data = await readChatFile(
        response.timeout(const Duration(seconds: 60)),
      );
      if (data.length != expectedSize) {
        throw const FormatException('文件下载不完整，请重试。');
      }
      return data;
    } on TimeoutException {
      throw const FormatException('文件下载超时，请重试。');
    } on IOException {
      throw const FormatException('下载失败，请检查网络后重试。');
    }
  }

  Future<Json> messages(
    String room, {
    int? after,
    int? before,
    bool wait = false,
  }) => request(
    'GET',
    'v1/rooms/$room/messages${Uri(queryParameters: {if (after != null) 'after': '$after', if (before != null) 'before': '$before', if (wait) 'wait': '8'})}',
  );

  Future<Json> sendMessage(
    String room,
    String content,
    String clientId,
  ) async =>
      (await request(
            'POST',
            'v1/rooms/$room/messages',
            body: {'body': content, 'clientId': clientId},
          ))['message']
          as Json;

  Future<void> recallMessage(int id) async {
    await request('DELETE', 'v1/messages/$id');
  }

  Future<void> reportMessage(int id, String reason) async {
    await request('POST', 'v1/messages/$id/report', body: {'reason': reason});
  }

  Future<Json> request(String method, String path, {Json? body}) async {
    try {
      final request = await _http
          .openUrl(method, base.resolve(path))
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (signedIn) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        final encoded = utf8.encode(jsonEncode(body));
        request.contentLength = encoded.length;
        request.add(encoded);
      }
      final response = await request.close().timeout(
        Duration(seconds: body?['kind'] == 'file' ? 60 : 15),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('服务器响应过大。');
        }
      }
      final value = jsonDecode(utf8.decode(bytes)) as Json;
      if (response.statusCode == 401) _token = '';
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException(value['error'] as String? ?? '讨论室请求失败，请稍后重试。');
      }
      return value;
    } on TimeoutException {
      throw const FormatException('连接超时。若刚发表了内容，请先刷新确认结果。');
    } on IOException {
      throw const FormatException('暂时无法连接讨论室，请检查网络后重试。');
    } on TypeError {
      throw const FormatException('服务器响应格式有误，请稍后重试。');
    }
  }

  Future<List<Json>> terms() async =>
      ((await request('GET', 'v1/terms'))['terms'] as List).cast<Json>();

  Future<List<DiscussionRoom>> match(Course course, String term) async =>
      ((await request(
                'POST',
                'v1/rooms/match',
                body: discussionMatchRequest(course, term),
              ))['rooms']
              as List)
          .map((value) => DiscussionRoom(value as Json))
          .toList();

  Future<Json> posts(String room, {int? before, int? parent}) => request(
    'GET',
    'v1/rooms/$room/posts${Uri(queryParameters: {if (before != null) 'before': '$before', if (parent != null) 'parent': '$parent'}).toString()}',
  );

  Future<void> publish(
    String room,
    String title,
    String content, {
    int? parent,
  }) async {
    await request(
      'POST',
      'v1/rooms/$room/posts',
      body: {'title': title, 'body': content, 'parent': ?parent},
    );
  }

  Future<void> deletePost(int id) async {
    await request('DELETE', 'v1/posts/$id');
  }

  Future<void> reportPost(int id, String reason) async {
    await request('POST', 'v1/posts/$id/report', body: {'reason': reason});
  }

  void close() => _http.close(force: true);
}
