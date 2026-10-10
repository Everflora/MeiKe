import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/jwc_news.dart';

String page({
  int index = 1,
  String href = '/2026/demo/page.htm',
  bool empty = false,
}) =>
    '''
<table><tr><td>navigation</td><td><a href="/main.htm">首页</a></td></tr></table>
<table>${empty ? '' : '''<tr><td>icon</td><td><a href="$href" class="main"><a href="$href" title="通知 &amp; 公告"><b>截断标题</b></a></a></td><td><div>2026-10-10</div></td></tr>'''}</table>
<ul class="wp_paging"><em class="curr_page">$index</em><em class="all_pages">3</em></ul>
''';
void main() {
  test('国际交流栏目 htm 跳转到 psp 时保持 HTTPS 和当前栏目，拒绝外部跳转', () {
    final current = JwcSection.international.pageUrl(1);
    expect(
      jwcRedirect(current, 'http://jwc.seu.edu.cn/gjjl/list.psp').toString(),
      'https://jwc.seu.edu.cn/gjjl/list.psp',
    );
    expect(
      () => jwcRedirect(current, 'https://evil.example/gjjl/list.psp'),
      throwsFormatException,
    );
    expect(() => jwcRedirect(current, '/jwxx/list.htm'), throwsFormatException);
  });
  test('8 个栏目对应官方地址，分页和缓存相互独立并保留旧最新动态缓存', () {
    expect(JwcSection.values.map((s) => s.label), [
      '最新动态',
      '教务信息',
      '学籍管理',
      '实践教学',
      '教学研究',
      '国际交流',
      '文化素质教育',
      '教师教学发展',
    ]);
    expect(
      JwcSection.academic.pageUrl(1).toString(),
      'https://jwc.seu.edu.cn/jwxx/list.htm',
    );
    expect(
      JwcSection.practice.pageUrl(2).toString(),
      'https://jwc.seu.edu.cn/sjjx/list2.htm',
    );
    final legacy = File('old/jwc-news.json');
    expect(JwcSection.latest.cacheFile(legacy).path, legacy.path);
    expect(
      JwcSection.values.map((s) => s.cacheFile(legacy).path).toSet().length,
      8,
    );
    expect(() => JwcSection.latest.pageUrl(0), throwsFormatException);
  });
  test('从发布日期行提取完整标题和原文链接，不包含导航，兼容嵌套链接', () {
    final parsed = JwcPage.parse(page());
    expect(parsed.items.length, 1);
    expect(parsed.items.single.title, '通知 & 公告');
    expect(parsed.items.single.date, '2026-10-10');
    expect(
      parsed.items.single.url,
      'https://jwc.seu.edu.cn/2026/demo/page.htm',
    );
    expect(parsed.pages, 3);
  });
  test('微信及校内 HTTP 链接转为 HTTPS，拒绝伪造域名和脚本链接', () {
    expect(
      noticeLink('http://news.seu.edu.cn/demo')?.toString(),
      'https://news.seu.edu.cn/demo',
    );
    expect(
      JwcPage.parse(
        page(href: 'https://mp.weixin.qq.com/s/demo'),
      ).items.single.url,
      'https://mp.weixin.qq.com/s/demo',
    );
    expect(noticeLink('javascript:alert(1)'), isNull);
    expect(noticeLink('https://jwc.seu.edu.cn.evil.example/a'), isNull);
    expect(noticeLink('https://user@jwc.seu.edu.cn/a'), isNull);
  });
  test('空表、重复首页和网站结构变化不能误报读取成功', () {
    expect(() => JwcPage.parse(page(empty: true)), throwsFormatException);
    expect(() => JwcPage.parse(page(), expectedPage: 2), throwsFormatException);
    expect(() => JwcPage.parse('<html>统一身份认证</html>'), throwsFormatException);
  });
  test('缓存分页去重，重启保留；刷新替换旧列表，不连续分页不能覆盖', () async {
    final directory = await Directory.systemTemp.createTemp('meike-jwc-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = JwcCache(File('${directory.path}/jwc.json'));
    await cache.save(JwcPage.parse(page()), refresh: true);
    await cache.save(
      JwcPage(
        [
          cache.items.single,
          const JwcNotice(
            '旧通知',
            '2026-10-09',
            'https://jwc.seu.edu.cn/older/page.htm',
          ),
        ],
        2,
        3,
      ),
      refresh: false,
    );
    expect(cache.items.length, 2);
    final reopened = JwcCache(cache.file);
    await reopened.load();
    expect(reopened.page, 2);
    expect(reopened.items.last.title, '旧通知');
    final original = await cache.file.readAsString();
    await expectLater(
      cache.save(const JwcPage([], 2, 3), refresh: false),
      throwsFormatException,
    );
    expect(await cache.file.readAsString(), original);
    await cache.save(JwcPage.parse(page()), refresh: true);
    expect(cache.items.length, 1);
    expect(cache.page, 1);
  });
}
