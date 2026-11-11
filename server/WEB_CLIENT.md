# 将已有梅课服务器接入 GitHub Pages

现有 API：`https://106.14.199.134/api/meike/`。沿用原数据库、Bearer 身份和讨论室，不迁移课程/聊天数据，不创建另一套服务器。

## 部署顺序

1. 用已有服务器密钥或云平台控制台连接 `admin@106.14.199.134`，确认目录为 `/home/admin/meike-discussion`，服务名为 `meike-discussion.service`。检查当前代码及服务配置，不直接覆盖与本分支不同的合作者更新。
2. 将线上 `app.py`、已有 `web_origins.py`（如果存在）及服务配置备份到权限为 0700 的独立备份目录。使用仓库的 `backup_database.py` 对现有 SQLite 做在线备份；不删除或重建数据库。
3. 将本分支 `server/app.py` 中的 CORS 改动合入线上文件，新增 `server/web_origins.py`。通过 Python 语法检查后替换；不要覆盖聊天、媒体或组队模块。
4. 新增独立 systemd drop-in `/etc/systemd/system/meike-discussion.service.d/web-origin.conf`：

```ini
[Service]
Environment="MEIKE_WEB_ORIGINS=https://everflora.github.io"
```

5. `sudo systemctl daemon-reload` 后只重启 `meike-discussion.service`，检查 active 状态与健康接口。已有 Nginx 能将 OPTIONS 转发到 Python（部署前返回 Python 的 501），正常情况下不需要修改 Nginx 或其他项目路由。
6. 在开发电脑运行只读门禁：

```sh
python3 tool/pwa/check_api.py
```

检查原生健康接口、允许来源的预检/健康、未登录的 401、非允许来源拒绝；不注册身份、不读取消息、不发送帖子。

7. 门禁通过后构建网页：

```sh
MEIKE_DISCUSSION_API=https://106.14.199.134/api/meike/ bash tool/pwa/build.sh /MeiKe-web/
```

需要时设置 `MEIKE_FLUTTER`。GitHub Actions 手动构建也可在 `discussion_api` 填入相同地址。将新产物更新到独立的公开发布仓库，不复制后端源码、密钥或数据库。

## 回滚

如果健康检查或原生鉴权失败，恢复备份的代码和该 drop-in 原始状态，重新 daemon-reload 并重启同一个服务；不回滚或覆盖运行中的数据库。发布门禁失败时保留现有静态网站。已发布网页可以重新构建不带 `MEIKE_DISCUSSION_API` 的版本暂时关闭讨论入口，保留用户本机课表。

## 数据与验证边界

网页首次连接需设置昵称/头像，本机身份与原生 App 不自动合并。教学班匹配、发言、图片/表情包和组队继续使用现有服务器。学校登录导入、劳动教育同步仍非本服务器接口。

发布前核对 `web/privacy.html` 中的数据流说明。真实收发验收需使用明确的测试身份和隔离教学班，不能向真实教学班发送演示消息。
