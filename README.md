<div align="center">
  <img src="./assets/app_icon.png" width="96" alt="梅课图标">
  <h1>梅课 MeiKe</h1>
  <p><strong>好好上课，不必等候。</strong></p>
  <p>面向东南大学的课表与校园信息工具 · Flutter 源码仓库</p>
  <p>
    <a href="https://106.14.199.134/">梅课官网</a> ·
    <a href="https://github.com/Everflora/MeiKe-site/releases/latest">Android 下载</a> ·
    <a href="https://everflora.github.io/MeiKe-web/">打开网页版</a>
  </p>
</div>

## 功能概览

| 模块 | 功能 |
| --- | --- |
| **课表与今天** | 整周课表、教学周切换、课程搜索与编辑、时间冲突提示、上课状态与倒计时 |
| **学校课表导入** | 在手机 App 内登录学校页面，读取课程、教师、地点、节次和周次，预览后合并或替换 |
| **校园信息** | 教务通知、劳动教育、素质讲座、离线校历，报名与选课以学校页面为准 |
| **讨论与组队** | 按学期和教学班匹配讨论室，支持群聊、招募、组队申请及基于自愿填写问卷的匹配 |
| **外观与备份** | 青梅、银杏、奶家日常三套主题，独立的明暗设置，以及 JSON 导入和导出 |

课表保存在本机，可离线编辑与查看。同一课程可设置多个常规安排、单双周及指定教学周的额外安排。教学周与日期按中国标准时间计算。项目由学生团队维护，校历、教务安排和报名结果以学校正式通知为准。

## 使用说明

**导入学校课表。** 从课表首页打开「一键导入学校课表」，在学校网页完成登录。学期选择优先使用学校返回的 2026–2027 学年秋季学期。导入预览默认将第一周周一设为 **2026 年 9 月 21 日**，同一学期已保存的日期优先，确认前可手动修改。默认合并会保留手动课程、颜色、备注和额外安排，确认替换前会保留原课表副本。账号与密码仅在学校网页输入。

**主题和讨论。** 默认主题为「奶家日常」，已有主题偏好继续生效。可在「我的 → 外观」切换主题、角色动效和奶蛋宠物。讨论室使用昵称与头像，课程匹配使用课程名、教师和上课时间；遇到多个候选教学班时由用户选择。

**课程组队。** 在教学班讨论室右上角进入，可浏览招募、创建队伍和申请加入。问卷答案仅本人可见，信息不足时不显示数字匹配分。讨论身份尚未绑定学籍，也不支持跨设备恢复。[课程组队实施说明](docs/TEAM_MATCHING_IMPLEMENTATION.md)

**在平台之间迁移。** 从原 SwiftUI 版或 Flutter 手机 App 导出 JSON，再在目标应用中导入。恢复会替换现有课表，建议先导出需要保留的数据。网页端可接收手机备份，学校登录相关操作跳转学校网页；公开网页版目前未开放讨论和组队。[网页版使用说明](https://github.com/Everflora/MeiKe-web#readme)

## 开发与构建

CI 固定使用 **Flutter 3.47.6**。SDK 约束、应用版本和构建号见 [pubspec.yaml](pubspec.yaml)。安装 [Flutter SDK](https://docs.flutter.dev/install)，并为目标平台安装对应工具链。

```sh
git clone https://github.com/Everflora/MeiKe.git
cd MeiKe
flutter doctor -v
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <设备ID>
```

| 目标 | 构建方式 |
| --- | --- |
| **Android · API 24+** | 配置 Android SDK，建议使用 JDK 21。运行 `flutter build apk --release`。仓库当前 release 构建使用调试签名，上架前需配置正式签名。 |
| **iOS · iOS 15+** | 在 macOS 上使用 Xcode。模拟器运行 `flutter build ios --simulator --debug`；真机需先在 `ios/Runner.xcworkspace` 配置 Runner 签名。 |
| **Web · GitHub Pages** | 在 Bash 中运行 `bash tool/pwa/build.sh /MeiKe-web/`，产物位于 `build/pages-repository/`。发布步骤及讨论 API 配置见 [PWA 部署说明](docs/PWA.md)。 |

提交前可运行以下检查。浏览器测试需要 Chrome。

```sh
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub --platform chrome test/web_storage_test.dart
node --test tool/pwa/pwa_test.mjs
```

学校课表解析可通过 `node --test tool/school_import_test.cjs` 验证。劳动教育的浏览器测试需按 [校园数据工具说明](tool/SCHOOL_CATALOG.md) 配置 Playwright 后运行 `node --test tool/labor_news_test.cjs`。

## 仓库结构

| 路径 | 职责 |
| --- | --- |
| [`lib/domain/`](lib/domain) | 课程模型、教学周、排课规则、学校字段转换 |
| [`lib/data/`](lib/data) | 课表文件与备份、校园信息缓存、讨论客户端 |
| [`lib/ui/`](lib/ui) | 课表、今天、讨论、校园和设置界面 |
| [`server/`](server) | 讨论与组队 API、SQLite 数据和部署工具 |
| [`web/`](web) · [`tool/pwa/`](tool/pwa) | PWA 入口、离线资源清单、发布工具 |
| [`test/`](test) | 业务、存储和界面测试，以及跨版本备份样本 |

## 项目文档

- [开发协作](CONTRIBUTING.md) · [架构与数据规则](docs/ARCHITECTURE.md) · [构建验证](docs/VALIDATION.md) · [路线图](docs/ROADMAP.md)
- [服务器部署](server/README.md) · [网页接入讨论 API](server/WEB_CLIENT.md) · [课程组队实现](docs/TEAM_MATCHING_IMPLEMENTATION.md)
- [奶家日常主题](docs/NAI_FAMILY_THEME.md) · [校历规则](docs/ACADEMIC_CALENDAR.md) · [校园数据工具](tool/SCHOOL_CATALOG.md)

学校课表和劳动教育适配分别参考 [SEUTimetable](https://github.com/sakimidare/SEUTimetable) 与 [SEU-Labor-Course-Pusher](https://github.com/zz6zz666/SEU-Labor-Course-Pusher)，相关说明见 [第三方声明](THIRD_PARTY_NOTICES.md)。测试数据使用演示课程，提交时请勿附上个人课表、学校账号或签名密钥。
