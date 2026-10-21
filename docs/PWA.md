# 梅课网页版 · GitHub Pages

网页版复用当前 Flutter 应用、课表数据模型和三套主题，以静态文件部署到 GitHub Pages。它是可添加到主屏幕的 PWA，不是 IPA，也不需要 Apple 开发者账号。已获授权发布到 [梅课网页版](https://everflora.github.io/MeiKe-web/)，公开产物仓库为 [Everflora/MeiKe-web](https://github.com/Everflora/MeiKe-web)，源码仓库保持私有。

## 功能范围

| 功能 | 网页版行为 |
| --- | --- |
| 整周课表、今天、课程编辑 | 支持；多次上课、单双周、额外安排沿用原规则 |
| 校历及停课、调课显示 | 沿用应用内校历与排课逻辑 |
| 青梅、银杏、奶家日常 | 支持；浅色、深色、跟随系统独立设置 |
| 奶蛋导航 | 支持，活动范围按实际网页画布计算 |
| 本地保存 | IndexedDB；写入失败会报错，不伪装成保存成功 |
| JSON 备份 | 可与手机 App 互相导入导出；不是自动云同步 |
| 离线使用 | 离线资源就绪后可查看、编辑本机课表及使用内置校历 |
| 学校课表自动读取 | 网页不能读取学校跨域登录会话；提供备份导入和学校官网入口 |
| 劳动教育、素质讲座、教务通知 | 打开官方网页，不在浏览器中模拟原生 WebView 登录抓取 |
| 讨论、课程组队 | 默认不连接；需要另行部署并配置支持跨域的 HTTPS 后端 |
| 原生小组件、系统悬浮窗 | 未提供 |

## iPhone 安装与数据

发布后，在 Safari 打开网址，点击「分享 → 添加到主屏幕」；系统提供「作为网页 App 打开」时将其开启。首次访问保持联网，等待「离线资源已就绪」提示后再断网。安装本身不会把原生 App 的数据迁移过来：请先在原生版「我的」中导出 JSON，再在网页「导入课表备份」中选择文件。

课表保存在当前浏览器的网站存储中，主屏幕应用与 Safari 标签页的存储行为可能随 iOS 版本变化。建议添加到主屏幕后再导入正式课表，并定期导出备份。无痕模式不适合作为长期课表存储。清理网站数据、系统回收存储、更换网址或发布路径，都可能影响数据；这些情况无法保证自动恢复。

目前已在桌面 Chromium 实测页面和离线启动，尚未在真实 iPhone Safari 上完成安装验收。不要将桌面验证当成所有 iOS 版本均已验证。

## 构建

使用 Flutter 3.47.6 / Dart 3.13.5、Node.js 及已安装的 iOS 原生开发依赖。先安装锁定的 Dart 依赖：

```sh
flutter pub get --enforce-lockfile
bash tool/pwa/build.sh /MeiKe-web/
```

Flutter 不在 PATH 时可设置 `MEIKE_FLUTTER=/absolute/path/to/flutter`。`/MeiKe-web/` 必须与发布仓库名称、大小写一致。用户或组织根站点仓库使用 `/`。不要直接用文件管理器打开 HTML；需通过 HTTP 本地预览或 HTTPS 发布。

输出目录：

- `build/web/`：可预览的完整站点。
- `build/pages-repository/`：可提交到独立发布仓库的站点和 Pages 工作流。

首次完整离线下载约 37.5 MB（包含中文字体、Flutter 渲染器和角色素材），浏览器首次渲染可早于缓存完成。全部运行字体和渲染器由本站提供，无需外部字体 CDN。网页构建不包含发布密钥；不得把凭证放入 `--dart-define`，它不是保密机制。

## 免费 GitHub Pages 发布

当前 `Everflora/MeiKe` 为私有源码仓库。建议保持其私有，**经团队确认后**建立公开的 `Everflora/MeiKe-web`，只提交 `build/pages-repository/` 的内容。编译产物及其中的图片、字体、客户端逻辑会公开，前端编译不等于加密。不要复制整个源码目录、学生课表、日志或签名证书。

1. 在独立发布仓库提交上述产物，默认分支为 `main`。
2. 在仓库 Settings → Pages → Build and deployment 中选择 GitHub Actions。
3. 运行产物自带的 Deploy MeiKe Pages 工作流。
4. 工作流成功后检查 Pages 返回的网址；预期路径为 `https://everflora.github.io/MeiKe-web/`，实际以 GitHub 返回结果为准。
5. 验证课表、备份和离线资源后再向同学分发网址或二维码。这里没有 IPA 安装包。

私有源码仓库的 Build MeiKe PWA 工作流只测试、构建并上传 artifact，不会自动公开发布。下载 `meike-pages-repository` artifact 后，将内容更新到发布仓库；保留隐藏文件 `.nojekyll` 和 `.github/workflows/pages.yml`。不要把构建产物加入私有源仓库。

## 离线与更新策略

每次构建生成资源 SHA-256 清单及内容版本。Service Worker 完整下载并校验全部资源后才可激活，部分下载或混合版本不会替换旧缓存；只缓存明确列出的静态资源，不缓存聊天接口、学校网页或认证响应。不同发布路径的缓存与 IndexedDB 相互隔离。

新版本下载完毕后显示「保存编辑后更新」。点击会重新打开页面；已保存的课表仍在 IndexedDB 中，未保存表单应先保存。静态缓存更新不会清空课表数据库。不联网时可继续使用已缓存版本，聊天及学校网页仍需要网络。

## 讨论室后端（可选）

GitHub Pages 只能托管静态文件，无法运行 Python/SQLite 服务。本次实现浏览器 HTTP 适配与后端精确来源校验，但没有修改或重启现有线上服务，也没有以真实用户身份测试网页聊天。

后端部署时设置 `MEIKE_WEB_ORIGINS=https://everflora.github.io`；多个来源用逗号分隔。来源只写协议、主机和端口，不带仓库路径，不允许 `*`。仅明确配置的本机开发来源允许 HTTP。反向代理需转发 OPTIONS 和应用返回的 CORS 响应头，避免自行叠加通配符。现有无 Origin 的原生客户端继续使用原鉴权。

前端构建可先运行以下命令，再运行 `node tool/pwa/finalize.mjs`：

```sh
flutter build web --release --no-pub --no-web-resources-cdn --no-wasm-dry-run \
  --base-href=/MeiKe-web/ \
  --dart-define=DISCUSSION_API=https://your-api.example
```

请将示例域名替换成团队真实 HTTPS API。浏览器使用现有 Bearer 身份机制，不共享学校网页登录 Cookie。启用前应另行验收昵称、消息、图片、组队、离线失败提示及跨域反向代理。当前文件发送的限制沿用主工程，不因网页构建而自动开放。

## 验证与维护

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub --platform chrome test/web_storage_test.dart
node --test tool/pwa/pwa_test.mjs
python3 -m unittest discover -s server
flutter build ios --release --no-codesign --no-pub
```

浏览器测试覆盖真实 IndexedDB 持久化、多安排与额外课程、原子替换、损坏记录保护和外观独立保存。离线测试覆盖下载失败保留旧缓存、站点缓存隔离、导航与隐私页面离线访问、API 不入缓存以及确定性产物清单。原生端继续使用 `dart:io` 和原有保存路径，JSON 版本不变。

2026-10-21 验证结果：静态分析通过，157 项原生 Flutter 测试、4 项 Chrome 存储与界面测试、4 项离线发布测试及 86 项后端测试通过；Web 发布构建和 iOS 无签名构建通过。浏览器中实际添加课程，停止本地 HTTP 服务后重新打开页面，课程和奶家主题均保留；已缓存版本更新后数据保留；实际下载 JSON 并再次导入，恢复 6 门演示课程成功。这些是本地验证，不表示线上后端或真实 iPhone 已验收。

新增浏览器能力时应扩展 `lib/platform/` 的明确子集，避免直接在共享代码引入新的 `dart:io` 专属 API。对学校跨域功能应说明浏览器限制，不通过禁用浏览器安全机制规避。

中文字体为 Google Fonts 发布的 Noto Sans SC，按 SIL Open Font License 分发；字体与许可位于 `web/assets/web-fonts/`。公开站点附有 `privacy.html`，发布前请核对实际数据流与团队联系方式。
