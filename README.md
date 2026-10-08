# 梅课 · MeiKe

Everflora 团队的 SEU 校园课程表项目。当前工程为「SEU综合课表」Flutter 1.2.0+4，从 SwiftUI 1.1.1 版迁移，安卓与 iOS 共用一套代码。业务逻辑与四个主要页面使用 Dart + Flutter，两个原生目录负责各自的应用入口和系统文件选择器。原 SwiftUI 工程在本地独立保留；此仓库以 Flutter 版本作为当前开发工程。App 内的显示名称暂沿用「SEU综合课表」。

## 已迁移功能

- 课表首页：七天整周、默认 13 节、明确的课间 / 午休 / 晚餐时间；正常竖屏自动适配高度，小屏与横屏可以滚动。仅保留上一周、周次选择、下一周和添加课程按钮。
- 课程录入：名称、教师、地点、备注，20 种课程颜色。
- 常规安排：一门课程支持多个上课安排；添加安排时可同时勾选周一、周四等多天；每项独立设置起止节次、起止周数、单双周，以及教师 / 地点覆盖。
- 额外安排：指定教学周和星期，支持全天实验、自定义开始结束时刻、单独的名称 / 教师 / 地点 / 备注。额外安排独立于单双周规则。
- 单节课保留地点；重叠课程并排显示，保存时提示时间冲突。点击课程可查看或编辑完整信息。
- 今天：正在上课、下一项安排、课间状态，按当前节次显示距离下课的秒级倒计时；全天实验不显示虚构的下课倒计时。
- 课程列表：搜索课程、教师、地点；编辑和删除课程。
- 设置：学期名称、开学周、教学周数，自定义节次，导入 / 导出 JSON 备份；空课表首页可以载入示例课程。
- 本地离线保存，读入失败时保留原文件；保存采用同目录临时文件刷新后替换。恢复损坏数据时先保留原文件副本。
- 沿用已选择的青绿色四牌楼大礼堂图标，支持系统深浅色模式。

尚未包含账号、云同步、讨论评价、组队、全校空教室、考试数据同步、AI 识别、小组件和悬浮窗。这些功能可在此项目上继续开发。

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
| `lib/ui/today_page.dart` | 今日课程与下课倒计时 |
| `lib/ui/course_editor.dart` | 课程、每周时间和额外时间编辑 |
| `lib/ui/courses_page.dart` | 搜索与课程列表 |
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

静态检查与 39 项自动测试已经通过，覆盖学校作息、教学周边界、每周多次安排、单双周、独立额外安排、正常课间不误报冲突、单节课地点、下课倒计时、窄屏 / 横屏、保存重启和损坏备份保护。

原 Swift 编码的演示备份能被 Flutter 导入，20 周展开课表与 Swift 结果逐字段一致；Flutter 重新导出的备份也通过原 Swift 解码器和全字段往返比较。

原生构建与运行验证结果见 `docs/VALIDATION.md`。

仓库不包含 Flutter / Android SDK、构建缓存、开发者账号、签名密钥或个人课表。克隆后按上面的步骤配置开发环境。iOS 开发团队配置留空，请在自己的 Xcode 中选择签名团队。

团队开发说明见 [CONTRIBUTING.md](CONTRIBUTING.md)，模块与数据规则见 [架构说明](docs/ARCHITECTURE.md)，后续功能设想见 [路线图](docs/ROADMAP.md)。
