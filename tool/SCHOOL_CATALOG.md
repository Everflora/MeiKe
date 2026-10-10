# 全校课表抓取与讨论室认定

独立浏览器由使用者手动登录，使用临时上下文，不读取或导出密码、Cookie、
浏览器存储和授权请求头。学校数据输出到 Git 忽略的
.local/school-analysis/，不要提交学校数据。

## 启动抓取

安装 Node.js 后运行 npm install --prefix .local/crawler playwright；
MEIKE_BROWSER_EXECUTABLE 指向本机 Chromium，代理可通过
MEIKE_BROWSER_PROXY 配置。运行 node tool/crawl_school.cjs，
在新窗口登录并查询全校课表。

通过 .local/school-analysis/control.json 发送单个指令，完成后写入
command-result.json。支持 status、terms、navigate、refresh-query、crawl。
使用 observed.json 中实际观察到的课程接口 key；先核对中文学期名称和
学校字典，不根据代码后缀猜学期。

本次核实：2026-2027-2 是 2026-2027学年秋季学期，2026-2027-3 是春季。
全校接口为 /jwapp/sys/kcbcx/modules/qxkcb/qxfbkccx.do，
表路径 datas.qxfbkccx，总数字段 totalSize，分页参数 pageNumber/pageSize。
每页间隔至少 500 毫秒，网络超时有限重试；总数变化、重复页、重复 WID、
学期不符或最终行数不符时停止输出。

保留教学班 ID、课序号、课程名、老师、排课文本，以及 SKBJ、BJDM、BJXX、
JXBMC、开课单位、校区、学分、课时等字段。字段返回空值时如实保留，
不将未提供的信息解释为抓取失败。

## 用户指定的认定规则

同一学期内，**课程名、老师、上课班级都相同，就认定为同一讨论室**。
教学班 ID、课程号、时间、周次、教室不阻止合并。教师和班级列表比较成员
集合，忽略逗号/顿号/分号、成员排序和首尾空格；不模糊匹配名称。
班级范围文本按原文本比较，不推断展开范围。

任一匹配字段缺失时暂按原教学班 ID 保留，并列入报告；缺失不是相同班级
的证据。每个讨论室保留全部 sourceIdentities 和不同排课安排。
原 ID 仍用于把个人课表条目映射到讨论室，但不再是完整信息记录的分组依据。

运行：
python tool/analyze_school_catalog.py .local/school-analysis/school-rows.json
python tool/test_school_catalog.py

输出：
- catalog.json：按当前规则整理的讨论室目录。
- discussion-rooms.csv：含上课班级、原 ID、排课信息的 Excel 可读分组表。
- report.json：统计、缺失字段和异常来源映射。
- class-room-mapping.json：每个原教学班标识到讨论室 roomKey 的映射。

当前 catalog.json 的 identity 支持 COURSE_TEACHER_CLASS，原教学班身份
保存在 sourceIdentities。后端已支持新身份和来源映射；应用用课程名、教师
及每周时间寻找对应讨论室。部署与接口说明见 server/README.md。
