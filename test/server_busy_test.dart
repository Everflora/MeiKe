import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/discussion_client.dart';

class BusyHeaders extends Fake implements HttpHeaders {
  BusyHeaders(this.retry);
  final String? retry;
  @override
  String? value(String name) => name == 'retry-after' ? retry : null;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  set contentType(ContentType? value) {}
}

class BusyResponse extends Stream<List<int>> implements HttpClientResponse {
  BusyResponse(String? retry) : headers = BusyHeaders(retry);
  @override
  final HttpHeaders headers;
  @override
  int get statusCode => 503;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode('<html>Service unavailable</html>')).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class BusyRequest extends Fake implements HttpClientRequest {
  BusyRequest(this.retry);
  final String? retry;
  @override
  HttpHeaders get headers => BusyHeaders(retry);
  @override
  set followRedirects(bool value) {}
  @override
  set contentLength(int value) {}
  @override
  void add(List<int> data) {}
  @override
  Future<HttpClientResponse> close() async => BusyResponse(retry);
}

class BusyTransport extends Fake implements HttpClient {
  BusyTransport(this.retry);
  final String? retry;
  int requests = 0;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    requests++;
    return BusyRequest(retry);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('503含非JSON正文仍显示明确重试提示，不自动重复写入', () async {
    final transport = BusyTransport('7');
    final client = DiscussionClient(
      sessionFile: File('unused'),
      transport: transport,
    );
    addTearDown(client.close);
    await expectLater(
      client.sendMessage('room', '消息', 'same-id'),
      throwsA(
        isA<ServerBusyException>()
            .having((e) => e.retryAfterSeconds, 'delay', 7)
            .having((e) => e.message, 'message', '服务器繁忙，请 7 秒后重试。'),
      ),
    );
    expect(transport.requests, 1);
  });
  test('重试时间有默认值和上下限，错峰等待不早于服务端要求', () async {
    for (final entry in <String?, int>{
      null: 3,
      'invalid': 3,
      '-1': 1,
      '120': 30,
    }.entries) {
      final client = DiscussionClient(
        sessionFile: File('unused'),
        transport: BusyTransport(entry.key),
      );
      try {
        await client.request('GET', 'v1/profile');
        fail('should reject');
      } on ServerBusyException catch (e) {
        expect(e.retryAfterSeconds, entry.value);
        expect(
          e.retryDelay.inMilliseconds,
          inInclusiveRange(entry.value * 1000, entry.value * 1000 + 999),
        );
      } finally {
        client.close();
      }
    }
  });
}
