import 'dart:convert';
import '../platform/io.dart';
import 'package:flutter/foundation.dart';
import '../domain/schedule.dart';

const laborNewsUrl = 'https://labor.seu.edu.cn/SJItemKaiKe/XuanKe/Index';
bool isLaborNewsUrl(Uri url) =>
    url.scheme == 'https' &&
    (url.host == 'labor.seu.edu.cn' || url.host.endsWith('.seu.edu.cn')) &&
    url.path.contains('/SJItemKaiKe/XuanKe/Index');

class NewsItem {
  NewsItem(this.data);
  final Json data;
  String get id => data['id'] as String;
  String field(String key) => data[key] as String? ?? '';
  String get name => field('name');
  bool get present => data['present'] == true;
  bool get unread => data['unread'] == true;
  bool get selectable =>
      present &&
      !field('enrollment').contains('已满') &&
      !field('deadline').contains('已截止');
  int get discovered => data['discovered'] as int;
}

class NewsStore extends ChangeNotifier {
  NewsStore(this.file);
  final File file;
  List<NewsItem> items = [];
  int? updated;
  bool writable = true, saving = false;
  String? loadError;
  static const maxBytes = 3 * 1024 * 1024;

  Future<void> load() async {
    try {
      if (!await file.exists()) return;
      if (await file.length() > maxBytes) throw const FormatException('新闻缓存过大');
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Json ||
          raw['version'] != 1 ||
          raw['items'] is! List ||
          (raw['items'] as List).length > 3000) {
        throw const FormatException('新闻缓存格式无效');
      }
      final loaded = <NewsItem>[];
      for (final item in raw['items'] as List) {
        if (item is! Json ||
            item['id'] is! String ||
            item['discovered'] is! int ||
            item['present'] is! bool ||
            item['unread'] is! bool) {
          throw const FormatException('新闻缓存内容无效');
        }
        _fields(item);
        loaded.add(NewsItem(item));
      }
      if (raw['updated'] != null && raw['updated'] is! int) {
        throw const FormatException('更新时间无效');
      }
      items = loaded;
      updated = raw['updated'] as int?;
    } catch (_) {
      writable = false;
      loadError = '本地新闻缓存无法读取，原文件已保留。可重新同步学校信息恢复。';
    }
    notifyListeners();
  }

  static Json _fields(Json raw) {
    final clean = <String, Object?>{};
    for (final key in [
      'itemId',
      'offeringId',
      'name',
      'category',
      'location',
      'time',
      'deadline',
      'enrollment',
      'teacher',
    ]) {
      final value = raw[key];
      if (value is! String || value.length > 2000) {
        throw const FormatException('学校课程信息格式无效，原列表未更改。');
      }
      clean[key] = value.trim();
    }
    if ((clean['name'] as String).isEmpty) {
      throw const FormatException('课程名称缺失，原列表未更改。');
    }
    return clean;
  }

  Future<int> sync(List<dynamic> rows, {DateTime? now}) async {
    if (saving) throw const FormatException('正在保存新闻，请稍候。');
    if (rows.length > 3000) throw const FormatException('学校课程列表过大。');
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final old = {for (final item in items) item.id: item};
    final next = <String, NewsItem>{};
    var added = 0;
    for (final row in rows) {
      if (row is! Json) throw const FormatException('课程列表格式无效。');
      final fields = _fields(row);
      final offering = fields['offeringId'] as String;
      final id = offering.isNotEmpty
          ? jsonEncode(['labor', fields['itemId'], offering])
          : jsonEncode([
              'labor',
              fields['name'],
              fields['time'],
              fields['location'],
              fields['category'],
              fields['teacher'],
            ]);
      if (next.containsKey(id)) throw const FormatException('学校返回重复课程，原列表未更改。');
      final previous = old[id];
      final isNew = previous == null && updated != null;
      if (isNew) added++;
      next[id] = NewsItem({
        ...fields,
        'id': id,
        'source': 'labor',
        'present': true,
        'discovered': previous?.discovered ?? timestamp,
        'unread': previous?.unread ?? isNew,
      });
    }
    // Keep unavailable courses as history; never report them as selectable.
    final history =
        old.values.where((item) => !next.containsKey(item.id)).toList()
          ..sort((a, b) => b.discovered.compareTo(a.discovered));
    for (final item in history.take(3000 - next.length)) {
      next[item.id] = NewsItem({...item.data, 'present': false});
    }
    final list = next.values.toList()
      ..sort((a, b) => b.discovered.compareTo(a.discovered));
    await _save(list, timestamp, recovering: !writable);
    return added;
  }

  Future<void> markRead(String id) async {
    if (saving ||
        !writable ||
        !items.any((item) => item.id == id && item.unread)) {
      return;
    }
    await _save([
      for (final item in items)
        item.id == id ? NewsItem({...item.data, 'unread': false}) : item,
    ], updated);
  }

  Future<void> _save(
    List<NewsItem> candidate,
    int? timestamp, {
    bool recovering = false,
  }) async {
    saving = true;
    try {
      final bytes = utf8.encode(
        jsonEncode({
          'version': 1,
          'updated': timestamp,
          'items': candidate.map((item) => item.data).toList(),
        }),
      );
      if (bytes.length > maxBytes) {
        throw const FormatException('新闻缓存过大，原列表未更改。');
      }
      await file.parent.create(recursive: true);
      if (recovering && await file.exists()) {
        await file.copy(
          '${file.path}.unreadable-${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      items = candidate;
      updated = timestamp;
      writable = true;
      loadError = null;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
