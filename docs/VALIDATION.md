# 移植验证记录

日期：2026-10-08。版本：Flutter 1.2.0+4。原版本：SwiftUI 1.1.1。

## 环境

- macOS arm64，Xcode 27.0（27A266a）。
- Flutter 3.47.6 stable，Dart 3.13.5。
- iOS 27.0 模拟器，iPhone 17e。
- iOS 26.6.2 真机，iPhone 15 Pro Max。
- 新应用标识：`cn.seutimetable.app`，与原 SwiftUI 版隔离。

## 已通过

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | No issues found |
| `flutter test --reporter expanded` | 39 / 39 通过 |
| Swift → Flutter 备份导入 | 原 Swift 编码器生成的 v1 演示备份可正确导入 |
| 20 周课程展开 | 与原 Swift 计算结果逐字段一致，含 UUID、周次、教师 / 地点覆盖、单双周和额外安排 |
| Swift → Flutter → Swift | 原 Swift 解码器可读取 Flutter 导出，全字段结果一致 |
| 本地文件 | 重启读取、编辑草稿隔离、失败不覆盖旧数据、损坏文件副本恢复通过 |
| Flutter 页面 | 390×844 整周 13 节，单节体育地点；320×568 与横屏无布局溢出；新增周一 / 周四课程与下课倒计时通过 |
| `flutter build ios --simulator --debug` | 成功，生成 `build/ios/iphonesimulator/Runner.app` |
| `flutter build ios --release --no-codesign` | 成功，生成 20.9 MB 的 `build/ios/iphoneos/Runner.app` |
| iOS 模拟器运行 | 已安装并启动，七天 / 13 节、课间、体育地点和指定周补课可见 |
| iOS 原生备份导出 / 恢复 | 使用系统文件选择器保存 JSON，再选择该文件恢复；显示「已恢复 5 门课程」 |
| 交付源码完整性 | 源码 ZIP 解压到干净目录，重新获取依赖、生成平台配置并成功编译 iOS 模拟器版 |
| iPhone 签名与安装 | Release 签名编译成功；Flutter 1.2.0+4 已独立安装并启动，原 SwiftUI 1.1.1 保留 |
| iPhone 数据迁移 | 原版备份通过 Flutter 解码验证后复制到新版；回读核对新旧文件，迁移完整且原版数据未改变 |

兼容测试与模拟器运行使用演示数据。真机迁移仅在本机与用户手机之间进行，个人课表和安装日志未纳入仓库。Flutter 转换与安装验证没有覆盖原 iPhone App。

## 验证范围

安卓工程、图标与平台插件已经接入，但本次尚未完成 Android APK 构建或安卓真机运行。需要由用户确认 Google Android SDK 许可后才能继续安装本机缺少的 Android SDK 构建包。已经通过的 Dart / Flutter 测试覆盖两端共用代码，不能替代 Android 原生编译及文件选择器真机验证。

真机使用本地开发签名，仓库不包含个人开发团队配置、证书或 provisioning profile。App Store 正式签名、商店提交、不同安卓设备适配与大字体无障碍测试不在以上通过记录之内。

未来的服务端、账号、社区与学校数据接入均未实现。
