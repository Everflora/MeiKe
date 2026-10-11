# 讨论室数据库

已建立在服务器 `admin@106.14.199.134`：
`/home/admin/meike-discussion/data/discussion.sqlite3`。
使用 SQLite 3，WAL 模式；不需要单独的数据库密码或开放数据库端口。
数据库由 admin 账户拥有，文件权限 600，目录权限 700。

当前数据为 2026-2027 学年秋季学期（2026-2027-2）：
4,279 个讨论室、4,492 条课程记录、4,492 个原教学班到讨论室的映射。
identities 表同时保存完整匹配身份和来源 ID，共 8,102 条。

| 表 | 内容 |
| --- | --- |
| academic_terms | 学期代码与名称 |
| rooms | 讨论室和分组后的课程、老师、上课班级、排课元数据 |
| identities | 三字段匹配身份、原教学班 ID 到讨论室的映射 |
| course_records | 原课程记录，完整保留本次抓取的班级和排课字段 |
| users | 讨论身份、昵称、头像 PNG BLOB、头像版本与身份令牌哈希 |
| messages | 聊天消息、发送标识、撤回状态；包含迁移的原帖子和回复 |
| message_events | 新消息、撤回、头像和昵称更新事件，供客户端增量接收 |
| message_reports | 聊天消息举报 |
| posts | 保留旧版本的帖子及回复，新增旧帖子同步到聊天消息 |
| reports | 旧版本帖子举报 |
| team_consents / group_rounds / team_default_rounds | 主动组队同意与教学班内默认组队场景 |
| team_profiles / team_preferences | 私有个人画像、活动意向和本次覆盖 |
| teams / team_members / team_applications | 团队、成员唯一关系及申请审核 |
| team_bans / team_avoidances | 本队移除限制与私密避开 |
| team_availability / team_feedback | 自愿抽象空闲时间与双方同意的匿名反馈 |

课程组队复用当前 Bearer 身份，匹配规则由独立 `team_matching` 模块和版本 JSON 配置提供。新表自动增量初始化，升级前在线备份，不重新导入课程或覆盖聊天数据。接口、边界和权限见 [课程组队实施说明](../docs/TEAM_MATCHING_IMPLEMENTATION.md)。

认定规则遵循用户指定：同学期内，课程名、老师集合、上课班级集合相同就
归入同一讨论室，不要求教学班 ID 或排课时间相同。669 条匹配字段不齐全
的记录按原教学班标识暂时保留。

服务器目录中的 imports 保存 catalog.json 和 school-rows.json 作为导入依据；
backups 保存一次 SQLite 在线备份。学校数据不提交 Git。

再次导入（在服务器项目目录执行）：

```sh
python3 app.py --db data/discussion.sqlite3 --catalog imports/catalog.json --course-records imports/school-rows.json
python3 check_database.py --db data/discussion.sqlite3 --catalog imports/catalog.json --course-records imports/school-rows.json
```

备份：

```sh
umask 077
python3 backup_database.py --db data/discussion.sqlite3 --output backups
```

验证包括 SQLite 完整性、外键、全部原教学班映射和全部课程字段一致性。
数据库测试覆盖多 ID 同室、重复导入、班级字段保留、冲突与事务回滚。
HTTPS API 已部署到 `https://106.14.199.134/api/meike/`。systemd 服务
`meike-discussion.service` 以 admin 运行，后端仅监听 `127.0.0.1:8765`；
Nginx 通过独立路径代理，不记录讨论 API 的访问日志。

应用首次设置头像和昵称创建身份；除健康检查和创建身份外，所有接口均验证 Bearer
身份。`POST /v1/rooms/match` 使用学期、课程名称、教师和每周上课时间匹配，
同一讨论室的所有原教学班时间一起参与匹配。返回多个候选时由用户确认班级。
周次按教学周计算，支持单双周、离散周与前后阶段，起止节次必须一致。

`GET/POST /v1/profile` 读取和修改当前身份的昵称、头像；修改不会创建新身份。
头像由应用居中裁剪为 128×128 PNG，保存在 users.avatar 中，读取路径为
`GET /v1/users/{userId}/avatar?version={avatarVersion}`，仍须 Bearer 身份。
Nginx 仅为 MeiKe API 放宽上传限制到 150k，服务端验证大小、PNG 校验与像素尺寸。

`GET/POST /v1/rooms/{roomKey}/messages` 用于历史消息与发送。`after` 是事件游标，
`before` 是历史消息 ID，二者不能同时使用；`wait=8` 等待最多 8 秒，期间每
250 毫秒检查新事件，客户端持续连接以自动更新消息。发送的 `clientId` 在身份
内唯一，重复请求返回同一条消息。昵称和头像修改、撤回也通过事件同步。
撤回接口 `DELETE /v1/messages/{id}` 仅允许本人；举报接口为
`POST /v1/messages/{id}/report`。首次升级自动迁移旧内容，重复启动不重复迁移。

维护服务：

```sh
sudo systemctl status meike-discussion.service
sudo systemctl restart meike-discussion.service
curl --fail https://106.14.199.134/api/meike/health
```

后端数据库与匹配业务测试：`python3 -m unittest discover -s server -p 'test_*.py'`。
线上验证只创建测试身份并读取匹配结果，没有向真实教学班发布测试帖子。
