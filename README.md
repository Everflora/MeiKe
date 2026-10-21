# 梅课 · MeiKe

Everflora 团队的 SEU 校园课程表项目。当前工程是从 SwiftUI 1.1.1 版迁移的 Flutter 应用，安卓与 iOS 共用一套代码，应用显示名称为「梅课」。业务逻辑与五个主要页面使用 Dart + Flutter，两个原生目录负责各自的应用入口和系统文件选择器。原 SwiftUI 工程在本地独立保留；此仓库以 Flutter 版本作为当前开发工程，版本号见 `pubspec.yaml`。

## 已迁移功能

- 课表首页：七天整周、默认 13 节，左侧分三行显示每节完整起止时间，连堂课程按节次分块；正常竖屏自动适配高度，小屏与横屏可以滚动。支持切换教学周、学校课表导入和添加课程。
- 课程录入：名称、教师、地点、备注，20 种课程颜色。
- 常规安排：一门课程支持多个上课安排；添加安排时可同时勾选周一、周四等多天；每项独立设置起止节次、起止周数、单双周，以及教师 / 地点覆盖。
- 额外安排：指定教学周和星期，支持全天实验、自定义开始结束时刻、单独的名称 / 教师 / 地点 / 备注。额外安排独立于单双周规则。
- 单节课保留地点；重叠课程并排显示，保存时提示时间冲突。点击课程可查看或编辑完整信息。
- 今天：正在上课、下一项安排、课间状态，按当前节次显示距离下课的秒级倒计时；全天实验不显示虚构的下课倒计时。
- 课程列表：搜索课程、教师、地点；编辑和删除课程。
- 设置：学期名称、开学周、教学周数，自定义节次，导入 / 导出 JSON 备份；空课表首页可以载入示例课程。
- 本地离线保存，读入失败时保留原文件；保存采用同目录临时文件刷新后替换。恢复损坏数据时先保留原文件副本。
- 沿用已选择的青绿色四牌楼大礼堂图标，支持青梅、银杏和奶家日常主题；跟随系统 / 浅色 / 深色单独设置。

学校课表导入使用学校网页登录；讨论室提供聊天与课程组队，新闻提供劳动教育选课及教务处通知。尚未包含独立学籍账号、课表云同步、全校空教室、考试数据同步、AI 识别、小组件和悬浮窗。

## GitHub Pages 网页版（PWA）

支持浏览器课表保存、课程编辑、JSON 备份迁移、三套主题和离线资源缓存，可由 iPhone Safari 添加到主屏幕。网页端不会读取学校网页登录会话；学校课程请手动添加或从手机 App 导出 JSON 后导入。讨论室默认关闭，需另行配置支持 HTTPS 和跨域的后端。

```sh
flutter pub get --enforce-lockfile
bash tool/pwa/build.sh /MeiKe-web/
```

发布产物位于 `build/pages-repository/`，包含 GitHub Pages 工作流；不包含 Dart 源码和后端源码。私有源码仓库继续保持私有，免费 Pages 可使用独立的公开产物仓库。完整功能范围、安装、离线行为和发布步骤见 [网页版说明](docs/PWA.md)。

## 奶家日常主题

在「我的 → 外观 → 主题」选择「奶家日常」。五个页面使用奶动物导航，课表显示当前课程高亮与奶蛋探头，「今天」使用黄色状态卡，讨论与校园使用角色插画。

点击边框上的奶蛋可展开半圆快捷导航。奶蛋站稳后播放一次连续的「安迪～」口型；拖动时保持直立，靠近左右边缘释放后吸附，在其他位置释放则回到拖动起点。「奶蛋宠物」与「角色动效」可分别关闭。

使用说明、实现入口、验证范围和演示截图见 [奶家日常主题说明](docs/NAI_FAMILY_THEME.md)。

## 课程智能组队

从每个教学班讨论室右上角「课程组队」进入。支持每个教学班默认一次组队、首次 10 题及后续 7+3 复用、LIGHT / STAGED / DEEP 合作模式、推荐理由、创建团队、申请审核、退出与关闭招募。P1 包含本次技能角色覆盖、显式技能角色需求及筛选、私密避开、自愿授权的共同空闲时间建议，以及全部成员同意后的匿名合作反馈。

题库、兼容度矩阵和权重集中在 `server/team_matching/config/rule-v1.0.json`，匹配引擎独立于 SQLite 和 HTTP。答案及可选 MBTI / 星座仅本人可见；Q9 与可选标签不计分。低于信息充分度阈值时不展示数字分数，共同时间也不参与规则分数。现有昵称账户未验证学籍，所属教学班由用户主动确认。架构、模型、接口及验证见 [课程组队实施说明](docs/TEAM_MATCHING_IMPLEMENTATION.md)。

## 一键导入学校课表

首页右上角下载图标或空课表上的「一键导入学校课表」打开学校办事大厅。请在学校网页完成登录，进入学生课表页面；应用自动读取，也可点击底部「读取课表」。若无法确定学期，会要求先选择学期。

「选择学期」默认选中学校返回的「2026-2027学年秋季学期」，仍可手动切换；若学校没有返回该学期，则保持未选择，避免使用不存在的学期代码。

导入预览展示课程、教师、教室、节次和周次。首次导入该学期需要选择第一教学周的周一；学校课程接口没有可靠的开学日期，应用不会猜测。默认合并，重复导入更新同一课程的安排并保留手动课程、颜色、备注和额外安排；可选择替换全部课程。确认保存前会在本机数据目录保留原课表副本。

支持不连续周、单双周、同课多个时间地点，拒绝不完整分页、无效周次及超出已有作息的节次，避免静默漏课。只通过校园 HTTPS 网页读取当前登录会话的课表字段，不读取登录表单或将账号密码发送到课表服务。校外入口可能需要学校 WebVPN；是否成功仍取决于学校当前网页与接口。

导入功能的接口字段参考 [SEUTimetable](https://github.com/sakimidare/SEUTimetable) 的公开校园适配，实际使用者课表不作为测试样本提交。Android 已完成构建；新增 WebView 的 iOS 构建与登录流程需在 macOS 上另行验证。

```sh
flutter analyze
flutter test
node --test tool/school_import_test.cjs
```

## 开发环境与运行

本次使用 Flutter 3.47.6 stable / Dart 3.13.5、Xcode 27.0 验证。项目要求 Flutter ≥ 3.38、Dart ≥ 3.10；建议团队统一使用本次验证的 Flutter 版本，并提交 `pubspec.lock`。

安装 [Flutter SDK](https://docs.flutter.dev/install/manual)，将它的 `bin` 加入 PATH，然后克隆仓库并在工程根目录运行：

```sh
git clone https://github.com/Everflora/MeiKe.git
cd MeiKe
```

```sh
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d <设备ID>
```

只生成应用而不运行：

```sh
# Android：安装 Android Studio / Android SDK，完成 SDK 许可与环境配置。
flutter build apk --debug
# 输出：build/app/outputs/flutter-apk/app-debug.apk

# iOS：需要 macOS、Xcode 和对应 iOS 模拟器运行时。
flutter build ios --simulator --debug
# 输出：build/ios/iphonesimulator/Runner.app

# iPhone release 编译验证；此命令不会签名，也不能直接安装到手机。
flutter build ios --release --no-codesign
```

安卓最低 Android 7.0 / API 24；iOS 最低 iOS 15。安卓使用 Flutter SDK 默认的 compileSdk / targetSdk 和 NDK 配置；本次 Flutter 版本的 compileSdk 为 36。Android 构建建议使用 JDK 21，首次构建会下载 Gradle 和所需 SDK / NDK 包。

新建 iPhone 调试安装：先 `flutter pub get`，用 Xcode 打开 `ios/Runner.xcworkspace`，选择 Runner → Signing & Capabilities，设置自己的开发团队，选已信任的 iPhone，运行。也可在签名配置完成后使用 `flutter run -d <设备ID>`。项目使用 Flutter 的 Swift Package Manager 集成。

本项目使用新的应用标识 `cn.seutimetable.app`，可与原 SwiftUI 测试版共存。Android 的 Kotlin namespace 为 `cn.seutimetable.seu_timetable`，不影响安装标识。发布到商店前应确定团队实际拥有的标识与正式签名；Android 模板的 release 配置目前仍使用调试签名，不能直接作为正式上架包。

## 迁移原 iPhone 课表

1. 在原 SwiftUI 版打开「设置 → 导出备份」，将 JSON 保存到「文件」或发到安卓手机。
2. 在 Flutter 版打开「设置 → 从备份恢复」，选择该 JSON。
3. 核对备份名称、课程数后确认替换。

恢复会替换 Flutter 版本的当前课表，请先导出需要保留的数据。两个版本数据目录互相隔离，不会自动读出另一款 App 的私有文件。

沿用 JSON `version: 1`，课程与安排的 UUID、颜色名称、单双周、额外安排和日期编码保持兼容。以中国标准时间计算课程日期和教学周，避免手机时区变化影响 SEU 上课时间。备份上限为 2,000,000 字节，未知版本、损坏文件和无效时间会拒绝导入。

也可用命令行检查并重新编码备份：

```sh
dart run tool/roundtrip_backup.dart 输入.json 输出.json
```

## 代码结构

| 路径 | 用途 |
| --- | --- |
| `lib/domain/schedule.dart` | 数据模型、上海时区、教学周、单双周、额外安排、冲突与课表布局计算、JSON 编码 |
| `lib/data/schedule_store.dart` | 本地文件保存、读取失败保护、备份恢复 |
| `lib/ui/timetable_page.dart` | 整周课表 |
| `lib/ui/school_import_page.dart`、`assets/school_import.js` | 校园网页登录、课表读取和导入预览 |
| `lib/domain/school_import.dart` | 校园课程字段转换、周次合并和重复导入 |
| `lib/ui/today_page.dart` | 今日课程与下课倒计时 |
| `lib/ui/course_editor.dart` | 课程、每周时间和额外时间编辑 |
| `lib/ui/courses_page.dart` | 搜索与课程列表 |
| `lib/ui/discussion_page.dart`、`lib/ui/chat_page.dart`、`lib/ui/discussion_profile.dart`、`lib/data/discussion_client.dart` | 课程匹配、群聊、头像与昵称 |
| `server/` | SQLite 后端、课程时间匹配、数据库维护与部署配置 |
| `lib/ui/settings_page.dart` | 学期 / 作息、演示数据、JSON 导入导出 |
| `lib/app.dart`、`lib/main.dart` | 主题、导航、启动与数据加载 |
| `android/`、`ios/` | 系统入口、插件、图标和构建配置 |
| `test/` | 业务、存储、界面测试与 Swift 兼容演示样本 |

`test/fixtures` 由原 Swift 模型生成，只包含演示课程，不包含使用者私人课表。`ios-occurrences.json` 是原 Swift 计算的 20 周结果，用于比对 Flutter 计算。

修改应用图标后运行：

```sh
dart run flutter_launcher_icons
```

## 验证

自动测试覆盖学校作息、教学周边界、每周多次安排、单双周、独立额外安排、正常课间不误报冲突、单节课地点、下课倒计时、窄屏 / 横屏、保存重启和损坏备份保护；新增学校导入的字段转换、重复导入、备份保护及模拟接口分页测试。

原 Swift 编码的演示备份能被 Flutter 导入，20 周展开课表与 Swift 结果逐字段一致；Flutter 重新导出的备份也通过原 Swift 解码器和全字段往返比较。

原生构建与运行验证结果见 `docs/VALIDATION.md`。

## 讨论室

底部「讨论室」中先设置头像和昵称，选择学期和自己的课程。已有讨论身份可
从右上角编辑资料；头像可从相册选择或恢复默认。应用只上传课程名称、
教师和每周上课的周次、星期、起止节次来匹配讨论室，不上传课程备注或群号。
个人课表中的一个阶段可以匹配全校课表的对应阶段；同一讨论室多个来源
教学班的时间会合并参与匹配。多个候选需要用户选择上课班级；没有匹配结果
时提示核对信息，不按课程名直接进入其他班。

讨论室采用群聊形式：底部输入消息后直接发送，消息自动更新，支持历史消息、
撤回本人的消息与举报。重试同一条消息不会重复发布，旧帖子与回复自动迁移。
昵称、128×128 PNG 头像、聊天记录保存在服务器 SQLite 数据库中，所有课程
使用同一份个人资料；头像接口也验证身份。讨论身份令牌保存在应用私有目录，
重新打开应用会读取服务器资料。当前没有跨设备账号登录或身份恢复功能。
课表仍可离线使用，讨论网络失败不修改课表。
默认 HTTPS 接口为 `https://106.14.199.134/api/meike/`；其他部署可通过
`--dart-define=DISCUSSION_API=https://你的地址/api/meike/` 配置。
数据库与后端维护说明见 [server/README.md](server/README.md)。

## 新闻

底部「校园」（新闻）提供「劳动教育」「教务通知」「校历」和「素质讲座」。劳动教育点击「同步」在学校网页完成登录，
课程列表出现后会自动读取；也可点击「读取课程通知」重试。读取完整的学校
课程表，展示项目名称、劳动类型、实施时间、地点、截止信息、选课情况和教师。
支持搜索、地点 / 类型筛选、仅看可选课程，以及从详情打开学校页面手动选课。

首次同步建立列表，后续新开课项目标记为新课程，打开详情后清除标记；满额、
截止和离开最新列表的课程保留为历史。新闻缓存与课表文件分开保存，离线
可以查看上次结果，读取失败不会覆盖已有新闻。显示的是最近同步结果，名额
和报名结果以学校网页为准。本版劳动教育采用手动同步，不提供后台推送。
账号和密码仅在学校登录网页中输入。

「素质讲座 → 进入素质讲座选课」在应用内打开学校讲座选课平台，使用学校登录进行查看和报名。提供学校首页和刷新按钮，复用学校HTTPS登录跳转处理。奶家主题暂用现有黑板插图；入口URL集中在 `lib/ui/lecture_selection_page.dart`。讲座信息和报名结果以学校网页为准。

「教务通知」接入 `https://jwc.seu.edu.cn/xxtz/list.htm`，无需登录，首次打开
自动刷新，展示通知标题与发布日期，支持搜索、下拉刷新及加载更早通知。
点击通知在应用内打开原文，兼容教务处栏目提供的校内与微信文章链接。
教务通知缓存单独保存，网络失败保留上次列表。
「教务处栏目」下拉菜单包含最新动态、教务信息、学籍管理、实践教学、
教学研究、国际交流、文化素质教育、教师教学发展。各栏目分别读取对应的
官方页面，独立保存缓存与分页；应用内切换保留已加载的历史页和搜索内容。
国际交流栏目跳转至 `.psp` 页面时保持 HTTPS。

课程表字段映射参考 [SEU-Labor-Course-Pusher](https://github.com/zz6zz666/SEU-Labor-Course-Pusher)，
许可证说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
网页读取测试：先按 `tool/SCHOOL_CATALOG.md` 安装本地 Playwright，再运行
`node --test tool/labor_news_test.cjs`，可通过 `MEIKE_BROWSER_EXECUTABLE` 指定 Chromium 路径。

仓库不包含 Flutter / Android SDK、构建缓存、开发者账号、签名密钥或个人课表。克隆后按上面的步骤配置开发环境。iOS 开发团队配置留空，请在自己的 Xcode 中选择签名团队。

团队开发说明见 [CONTRIBUTING.md](CONTRIBUTING.md)，模块与数据规则见 [架构说明](docs/ARCHITECTURE.md)，后续功能设想见 [路线图](docs/ROADMAP.md)。
