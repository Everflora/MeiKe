# 开发说明

工程根目录即 Flutter 项目目录，克隆后可以直接在 Android Studio、VS Code 或终端中开发，无需再寻找子工程。

## 开始开发

1. 准备 Flutter 3.47.6 stable，并通过 `flutter doctor -v` 检查所需平台环境。
2. 执行 `flutter pub get` 获取依赖。`pubspec.lock` 已提交，用于统一团队依赖版本。
3. 用 `flutter devices` 获取模拟器 / 手机 ID，再用 `flutter run -d <设备ID>` 启动。
4. iPhone 签名需要在 Xcode 中选择自己的团队；Android SDK 路径保存在本地的 `android/local.properties`。

提交前可运行：

```sh
dart format lib test tool
flutter analyze
flutter test
```

修改课程规则、备份或时间计算时，补充对应的业务测试。修改系统文件选择器、签名、插件或权限时，除 Flutter 测试外，还需在受影响的平台编译和运行验证。构建示例见根目录 README。

## 数据与兼容性

- 当前备份格式为 `version: 1`，兼容原 SwiftUI 版。现有字段名、UUID、颜色枚举值和日期格式属于兼容约定。
- 编辑页使用数据副本，保存通过 `ScheduleStore` 进行；避免直接修改已加载的数据后绕过保存。
- 课程时间按中国标准时间计算。单双周按学期教学周编号判断，不能替换为一年中的自然周。
- 自动测试样本只使用演示数据。不要把真实学生课表、账号、证书或本地运行日志提交到仓库。
- 新增云服务时，优先保留离线课表能力，再把网络与同步职责拆到独立模块。

## 平台文件

`android/gradlew`、`android/gradlew.bat` 和 Gradle Wrapper JAR 一并提交，方便跨机器构建。Gradle、Flutter 和 iOS 插件的生成目录不提交，获取依赖 / 构建时会重新生成。

当前仓库没有配置自动 CI 或商店发布流水线；`docs/VALIDATION.md` 记录的是已完成的本地验证，不表示每次提交都自动构建了两个平台。

建议通过独立分支和 Pull Request 协作，在描述中说明最终行为、相关验证和仍待验证的平台范围。
