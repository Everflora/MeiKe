# 讨论室表情包与文件（1.4.0+13）

## 使用

- 聊天框旁的笑脸打开收藏表情包。点按即发送，长按可移除；收藏随当前讨论身份保存。
- 长按图片/表情包消息可「添加到表情包」，查看大图时右上角也有收藏入口。
- 收藏面板「＋」支持从相册添加，或从文件导入图片/GIF；GIF 保留动画。图片/表情包继续使用原来的大小和收藏限额。
- 聊天框旁「＋ → 文件」打开系统文件选择器；显示文件名、大小，明确点击发送后上传。取消选择和取消待发送文件不会清空文字草稿。
- 文件卡片显示名称和大小，点开后「下载并保存到手机」调用系统保存对话框，iOS 可选择「文件」中的保存位置，Android 使用系统文件选择器。
- 单个文件非空且不超过 10 MiB。传输不更改原文件内容；PDF、Office 文档、压缩包等均作为文件发送。
- 失败保留待发送文件和 clientId，重试不会产生重复消息；文件支持原有撤回和举报。文件不可收藏成表情包。

## 接口与兼容

沿用 `POST /v1/rooms/{roomKey}/messages`，文件提交 `kind: file`、`fileName`、`media`（Base64）、`clientId`。返回 `file: {name,size}`；列表不内嵌文件内容。旧客户端看到 `[文件] 文件名` 占位，图片/文字/收藏表情包接口保持兼容。

下载沿用 `GET /v1/messages/{id}/media`，验证 Bearer 身份，返回 `application/octet-stream`、`Content-Disposition: attachment` 和 UTF-8 文件名。文件不在服务器执行或按上传 MIME 渲染，不写入客户端指定的文件路径。文件名限制为 240 UTF-8 字节，禁止路径分隔符、控制字符与双向文本覆盖符；同一 nonce 的文件名或内容冲突返回 409。

数据库增量增加 messages.file_name、file_size，字节复用 message_media。首次启动自动迁移，重复启动不重复迁移；无需重导课程、重建身份或清空消息。现有媒体频率（10 条/分钟）和 24 小时 100 MiB 总量约束继续作用于图片、表情和文件。撤回删除附件字节并通过原事件游标同步。

## 部署顺序（客户端与后端均需更新）

此文档是部署说明，**不代表线上已经部署**。当前开发机没有 106.14.199.134 的可信 SSH 主机记录，未修改线上服务或代理，也未在真实讨论室发送测试消息。

1. 在已认证的现有 SSH 连接中，进入 `/home/admin/meike-discussion`。先进行在线备份，并复制现有 server 源文件到一个新的恢复目录；保留现有 data、imports、backups、systemd 和 Nginx 配置。

   ```sh
   umask 077
   python3 backup_database.py --db data/discussion.sqlite3 --output backups
   ```

2. 更新 `app.py`、`chat.py`、`chat_stickers.py`，新增 `chat_files.py`。其余后端文件使用现有完整版本。UI PR #7 已进入 main；文件 PR #8 合入的是原 UI 分支，因此本次完整整合 PR 直接基于 main，部署时使用包含文件功能的版本。

3. Nginx 现有 MeiKe API 代理上限为 5m，10 MiB 文件经过 Base64 约为 13.34 MiB。仅在现有 `/api/meike/` location 中将 `client_max_body_size` 调为 `15m`，不要修改其他站点或关闭 TLS、身份验证；检查配置并 reload。

   ```sh
   sudo nginx -t
   sudo systemctl reload nginx
   ```

4. 在独立临时数据库运行测试（不使用线上 data），随后重启现有服务。

   ```sh
   python3 -m unittest discover -s /path/to/checkout/server -p 'test_*.py'
   sudo systemctl restart meike-discussion
   sudo systemctl is-active meike-discussion
   ```

5. 后端和代理就绪后安装客户端，验证小文件与大于 4 MiB 的文件发送/保存、重复重试、撤回后不可下载以及 GIF 收藏重发。真实讨论室收发由用户本人验证。

回退时恢复旧源文件并重启；新增可空数据库列保持兼容。旧客户端只显示文件占位，旧后端不能接收新文件类型，因此回退后先暂停文件发送。不要为回退删除数据库或重建身份。

## 验证

Flutter 静态检查、101 项 Flutter 测试和 70 项后端测试通过。文件测试覆盖字节和中文名保留、上传界限、路径/控制符拒绝、HTTP 大于图片上限的上传、鉴权下载、下载附件头、重启、同标识重试与冲突、撤回删除、文件不可收藏为表情包；客户端交互测试覆盖确认发送、断网重试、下载保存、取消时文字草稿保留，以及小屏大字模式下长文件名的保存按钮可达性。

iOS 模拟器已通过系统「文件」保存窗口保存 73 字节的中文名测试文档，返回「已保存到所选位置」；原生选文件窗口正常打开。此验证使用项目外的离线测试入口，未访问真实讨论室，测试入口不包含在提交中。

Android 系统保存流程使用现有跨平台 FilePicker API，尚未完成 Android 真机验证；iPhone 客户端安装与线上部署状态见 PR。
