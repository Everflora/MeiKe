# 服务器容量保护

后端采用线程和SQLite，容量保护用于控制资源占用与过载行为，不代表千人并发承诺。

所有默认值集中在 `server/capacity.py`，可通过systemd服务环境变量调整。启动时校验正整数范围、请求数不超过连接数、媒体处理数不超过请求数。

| 环境变量 | 默认 | 含义 |
|---|---:|---|
| MEIKE_MAX_CONNECTIONS | 160 | 同时接入的连接/处理线程上限；空闲长连接也计入 |
| MEIKE_MAX_REQUESTS | 128 | 同时处理的普通HTTP请求数；聊天等待新消息也计入 |
| MEIKE_MAX_POLLS | 96 | 等待新消息的长轮询上限，必须小于普通请求数，为短请求预留32个额度 |
| MEIKE_MAX_UPLOADS | 1 | 图片/GIF上传、收藏及发送已保存表情包同时处理数 |
| MEIKE_MAX_DOWNLOADS | 2 | 消息媒体、收藏媒体和头像同时读取并发送数 |
| MEIKE_MAX_BACKLOG | 128 | 内核等待accept的连接队列请求值；与已接入连接上限不同 |
| MEIKE_MAX_RETRY_AFTER | 3 | 过载提示等待秒数，范围1至30 |

聊天文字发送不占媒体上传额度。大媒体请求在读取和解码JSON/Base64前检查上传额度，小请求的图片/GIF及收藏转发也进入同一额度。媒体下载在查询BLOB前检查，额度保持到响应发送结束。历史文件下载兼容保留；新文件上传仍关闭。

达到额度时不继续排队占用业务资源，而返回HTTP503、JSON错误代码和Retry-After秒数。代码为SERVER_BUSY、POLL_BUSY、UPLOAD_BUSY、DOWNLOAD_BUSY；SQLite锁繁忙异常映射为DATABASE_BUSY。GET /health不占普通请求额度，但仍受总连接数限制。

拒绝未读上传时关闭当前HTTP连接，先发送响应，再在限定时间内以小块丢弃上游残留字节，避免缓存整个被拒绝的附件。主连接接入超限时无需增加线程便可拒绝。请求成功、异常或客户端断开均释放额度。

客户端503显示「服务器繁忙，请N秒后重试」。聊天轮询按Retry-After等待并增加0至999毫秒随机错峰；消息发送失败保留原草稿和clientId，由用户确认重试，不自动重发写入操作。无效或缺失Retry-After使用3秒；客户端等待秒数限制在1至30之间。

上线需部署app.py和capacity.py并重启服务；数据库无结构改动。与文件上传移除一起部署时，还需同步chat.py、chat_files.py。先备份源码和数据库，失败时回退源码即可。

## 通知及进程保护

`room_events.py` 用固定64组条件变量唤醒等待者，发送、撤回和资料更新提交到SQLite后才通知。空闲时每4秒补查游标，通知丢失不会丢掉已提交消息。发送失败仍不自动排队重发业务写入。

设置 `MEIKE_REDIS_URL` 并安装 `requirements-redis.txt` 后，使用Redis Pub/Sub跨进程通知。只有一个订阅线程和一个发送线程；通知发送队列最多128个房间标识，不包含消息正文、账号或令牌。队列满时跳过额外通知，客户端通过游标补查。Redis不可用时本进程唤醒仍工作，跨实例最多等待补查，重连带退避。`/health` 的 `notifications` 为redis或local，后者表示本地模式或正在降级。

Redis Pub/Sub本身不是持久消息队列，因此消息先落SQLite，发送成功仅在数据库提交后返回。[Redis官方说明](https://redis.io/docs/latest/develop/use-cases/pub-sub/)

线上梅课Redis使用独立容器和私有Unix套接字，网络关闭，无TCP端口；容器硬内存64MiB、CPU0.2核、进程32。Redis数据预算16MiB、客户端16、输出缓冲限额独立设置；不存储聊天正文或附件，不改动其他项目的Redis。`maxmemory`不覆盖所有缓冲开销，所以另设容器硬内存上限。[Redis官方说明](https://redis.io/docs/latest/develop/reference/eviction/)

后端systemd限制：MemoryHigh=192MiB、MemoryMax=256MiB、MemorySwapMax=0、CPUQuota=100%、TasksMax=192，异常3秒后重启。硬限制用于保护主机；服务进程本身仍可能被限制终止或遭遇其他故障，不能承诺永不停止。Redis容器自动重启，后端可降级继续使用数据库。

Redis连接是可选能力，开发环境不安装Redis客户端仍运行本地通知。线上使用固定redis-py6.4.0私有目录，启动环境的PYTHONPATH指向该目录，无全局Python包替换。

## 代理入口

Nginx仅在 `/api/meike/` 设置 `limit_conn meike_api_connections 200`，按 `$server_name` 统计正在处理的请求，超额返回503 JSON及3秒Retry-After，避免按校园出口IP限制所有同学。该限制在完整请求头读入后生效，不是所有TCP连接的总数限制；HTTP/2并发请求单独计数。[Nginx官方说明](https://nginx.org/en/docs/http/ngx_http_limit_conn_module.html)

共享区定义见 `server/nginx-capacity-zone.conf`，应在http层include；限额指令和繁忙响应命名location仅添加到梅课所在server，其他项目路由未添加限制。上传读取空闲超时10秒，向上游发送和向客户端发送的空闲超时15秒，上传大小仍为15m。独立Nginx测试验证超额503、Retry-After、额度恢复与其他路由可用；上线前nginx -t通过，使用reload，不替换已有证书或其他代理路由。

验证包括容量设置、连接上限后的恢复、请求满载时健康检查、上传体未发送即拒绝、实际大上传的503响应、保存表情包限额、异常释放、下载响应完整性，以及客户端过载提示和重试时间边界。另用独立模拟数据库、本机HTTP和资源上限进行100人接入及GIF并发复测；该测试不包含Nginx、公网或长时间满载。
