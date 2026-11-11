import 'dart:async';
import 'dart:convert';
import '../platform/io.dart';
import 'package:html/parser.dart' as html;
import '../domain/schedule.dart';

const jwcNewsUrl = 'https://jwc.seu.edu.cn/xxtz/list.htm';

enum JwcSection {
  latest('最新动态', 'zxdt'),
  academic('教务信息', 'jwxx'),
  registration('学籍管理', 'xjgl'),
  practice('实践教学', 'sjjx'),
  research('教学研究', 'jxyj'),
  international('国际交流', 'gjjl'),
  culture('文化素质教育', 'cbxx'),
  faculty('教师教学发展', 'jfzx');

  const JwcSection(this.label, this.path);
  final String label, path;
  Uri pageUrl(int page) {
    if (page < 1 || page > 500) throw const FormatException('通知页码无效。');
    return Uri.parse(
      'https://jwc.seu.edu.cn/$path/list${page == 1 ? '' : page}.htm',
    );
  }

  File cacheFile(File legacy) =>
      this == latest ? legacy : File('${legacy.parent.path}/jwc-$path.json');
}

Uri jwcRedirect(Uri current, String location) {
  final target = current.resolve(location);
  if (!['http', 'https'].contains(target.scheme) ||
      target.host != 'jwc.seu.edu.cn' ||
      target.userInfo.isNotEmpty ||
      target.pathSegments.firstOrNull != current.pathSegments.firstOrNull) {
    throw const FormatException('教务处重定向地址无法识别，请稍后重试。');
  }
  return target.replace(scheme: 'https');
}

Uri? noticeLink(String value) {
  final url = Uri.parse(jwcNewsUrl).resolve(value);
  if (!['http', 'https'].contains(url.scheme) ||
      url.userInfo.isNotEmpty ||
      !(url.host == 'seu.edu.cn' ||
          url.host.endsWith('.seu.edu.cn') ||
          url.host == 'mp.weixin.qq.com')) {
    return null;
  }
  return url.replace(scheme: 'https');
}

class JwcNotice {
  const JwcNotice(this.title, this.date, this.url);
  final String title, date, url;
  Json toJson() => {'title': title, 'date': date, 'url': url};
}

class JwcPage {
  const JwcPage(this.items, this.page, this.pages);
  final List<JwcNotice> items;
  final int page, pages;
  static JwcPage parse(String source, {int expectedPage = 1}) {
    final doc = html.parse(source);
    final paging = doc.querySelector('.wp_paging');
    final current = int.tryParse(
      paging?.querySelector('.curr_page')?.text.trim() ?? '',
    );
    final pages = int.tryParse(
      paging?.querySelector('.all_pages')?.text.trim() ?? '',
    );
    if (current != expectedPage ||
        pages == null ||
        pages < current! ||
        pages > 500) {
      throw const FormatException('教务处页面结构发生变化，请稍后重试。');
    }
    final items = <JwcNotice>[];
    final seen = <String>{};
    final modernRows = doc.querySelectorAll('.news-list-item');
    for (final row
        in modernRows.isNotEmpty ? modernRows : doc.querySelectorAll('tr')) {
      final cells = row.children.where((e) => e.localName == 'td').toList();
      final modern = modernRows.isNotEmpty;
      if (!modern && cells.length != 3) continue;
      final date = modern
          ? row.querySelector('.news-item-date-ym')?.text.trim() ?? ''
          : cells.last.text.trim();
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
        if (modern) throw const FormatException('通知日期无法识别，原列表已保留。');
        continue;
      }
      final links = modern
          ? row.querySelectorAll('.news-item-title a[href]')
          : cells[1].querySelectorAll('a[href]');
      if (links.isEmpty) throw const FormatException('通知链接缺失，未更新列表。');
      final link = links.last;
      final title = (link.attributes['title'] ?? link.text)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final url = noticeLink(link.attributes['href']!);
      if (title.isEmpty ||
          title.length > 1000 ||
          url == null ||
          url.toString().length > 4000) {
        throw const FormatException('通知信息格式无法识别，未更新列表。');
      }
      if (seen.add(url.toString())) {
        items.add(JwcNotice(title, date, url.toString()));
      }
    }
    if (items.isEmpty || items.length > 100) {
      throw const FormatException('未找到教务通知，原列表已保留。');
    }
    return JwcPage(items, current, pages);
  }
}

class JwcNewsClient {
  final HttpClient http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  Future<JwcPage> fetch(
    int page, {
    JwcSection section = JwcSection.latest,
  }) async {
    if (page < 1 || page > 500) throw const FormatException('通知页码无效。');
    try {
      var url = section.pageUrl(page);
      HttpClientResponse? received;
      for (var attempt = 0; attempt < 4; attempt++) {
        final request = await http
            .getUrl(url)
            .timeout(const Duration(seconds: 20));
        request.followRedirects = false;
        final reply = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if ([301, 302, 303, 307, 308].contains(reply.statusCode)) {
          final location = reply.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('教务处跳转地址缺失。');
          url = jwcRedirect(url, location);
          await reply.drain<void>().timeout(const Duration(seconds: 20));
        } else {
          received = reply;
          break;
        }
      }
      final response = received;
      if (response == null) throw const FormatException('教务处跳转次数过多，请稍后重试。');
      if (response.statusCode != 200) {
        throw const FormatException('教务处网站暂时不可用，请稍后重试。');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('教务处页面过大。');
        }
      }
      return JwcPage.parse(utf8.decode(bytes), expectedPage: page);
    } on TimeoutException {
      throw const FormatException('教务处连接超时，请下拉刷新重试。');
    } on IOException {
      throw const FormatException('无法连接教务处，请检查网络后重试。');
    }
  }

  void close() => http.close(force: true);
}

class JwcCache {
  JwcCache(this.file);
  final File file;
  List<JwcNotice> items = [];
  int page = 0, pages = 0;
  int? updated;
  Future<void> load() async {
    if (!await file.exists()) return;
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('教务通知缓存过大。');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Json ||
        data['version'] != 1 ||
        data['items'] is! List ||
        data['page'] is! int ||
        data['pages'] is! int ||
        data['updated'] is! int ||
        data['page'] < 1 ||
        data['pages'] < data['page'] ||
        data['pages'] > 500 ||
        (data['items'] as List).length > 10000) {
      throw const FormatException('教务通知缓存无效。');
    }
    final loaded = <JwcNotice>[];
    for (final raw in data['items'] as List) {
      if (raw is! Json ||
          raw['title'] is! String ||
          raw['date'] is! String ||
          raw['url'] is! String ||
          (raw['title'] as String).isEmpty ||
          noticeLink(raw['url'])?.toString() != raw['url']) {
        throw const FormatException('教务通知缓存无效。');
      }
      loaded.add(JwcNotice(raw['title'], raw['date'], raw['url']));
    }
    items = loaded;
    page = data['page'];
    pages = data['pages'];
    updated = data['updated'];
  }

  Future<void> save(JwcPage result, {required bool refresh}) async {
    if (!refresh && result.page != page + 1) {
      throw const FormatException('通知分页不连续，请刷新重试。');
    }
    final merged = <String, JwcNotice>{
      if (!refresh)
        for (final item in items) item.url: item,
    };
    for (final item in result.items) {
      merged[item.url] = item;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final bytes = utf8.encode(
      jsonEncode({
        'version': 1,
        'items': merged.values.map((e) => e.toJson()).toList(),
        'page': result.page,
        'pages': result.pages,
        'updated': timestamp,
      }),
    );
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('教务通知缓存过大。');
    }
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(file.path);
    items = merged.values.toList();
    page = result.page;
    pages = result.pages;
    updated = timestamp;
  }
}
