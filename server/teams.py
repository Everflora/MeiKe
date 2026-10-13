"""Authenticated team workflows. Matching never reads SQL or HTTP state."""
import datetime
import json
import secrets
import time
from team_matching import CONFIG, validate_answers, validate_requirements, match_team

NOT_HANDLED = object()


def initialize(db):
    db.executescript('''
      CREATE TABLE IF NOT EXISTS team_consents (
        user_id TEXT REFERENCES users(id), offering_id TEXT REFERENCES rooms(id),
        created INTEGER NOT NULL, PRIMARY KEY(user_id,offering_id));
      CREATE TABLE IF NOT EXISTS team_profiles (
        user_id TEXT PRIMARY KEY REFERENCES users(id), answers TEXT NOT NULL,
        version INTEGER NOT NULL, tags TEXT NOT NULL DEFAULT '{}');
      CREATE TABLE IF NOT EXISTS group_rounds (
        id TEXT PRIMARY KEY, offering_id TEXT NOT NULL REFERENCES rooms(id),
        name TEXT NOT NULL, creator_id TEXT NOT NULL REFERENCES users(id), created INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS group_rounds_offering ON group_rounds(offering_id,created);
      CREATE TABLE IF NOT EXISTS team_default_rounds (
        offering_id TEXT PRIMARY KEY REFERENCES rooms(id),
        round_id TEXT NOT NULL UNIQUE REFERENCES group_rounds(id));
      CREATE TABLE IF NOT EXISTS team_preferences (
        user_id TEXT REFERENCES users(id), round_id TEXT REFERENCES group_rounds(id),
        answers TEXT NOT NULL, overrides TEXT NOT NULL DEFAULT '{}',
        can_meet_offline INTEGER NOT NULL DEFAULT 0, willing_invites INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL, PRIMARY KEY(user_id,round_id));
      CREATE TABLE IF NOT EXISTS teams (
        id TEXT PRIMARY KEY, round_id TEXT NOT NULL REFERENCES group_rounds(id),
        leader_id TEXT NOT NULL REFERENCES users(id), name TEXT NOT NULL,
        capacity INTEGER NOT NULL CHECK(capacity BETWEEN 2 AND 12), mode TEXT NOT NULL,
        offline INTEGER NOT NULL DEFAULT 0, needs_meeting INTEGER NOT NULL DEFAULT 0,
        skills TEXT NOT NULL, roles TEXT NOT NULL, description TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('RECRUITING','FULL','CLOSED')),
        published INTEGER NOT NULL DEFAULT 0, completed INTEGER NOT NULL DEFAULT 0,
        version INTEGER NOT NULL DEFAULT 1, created INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS teams_round ON teams(round_id,created);
      CREATE TABLE IF NOT EXISTS team_members (
        team_id TEXT REFERENCES teams(id), user_id TEXT REFERENCES users(id),
        round_id TEXT NOT NULL REFERENCES group_rounds(id), joined INTEGER NOT NULL,
        PRIMARY KEY(team_id,user_id), UNIQUE(round_id,user_id));
      CREATE TRIGGER IF NOT EXISTS team_capacity_guard BEFORE INSERT ON team_members BEGIN
        SELECT CASE WHEN (SELECT COUNT(*) FROM team_members WHERE team_id=NEW.team_id) >=
          (SELECT capacity FROM teams WHERE id=NEW.team_id) THEN RAISE(ABORT,'TEAM_FULL') END;
        SELECT CASE WHEN NEW.round_id != (SELECT round_id FROM teams WHERE id=NEW.team_id)
          THEN RAISE(ABORT,'ROUND_MISMATCH') END;
      END;
      CREATE TABLE IF NOT EXISTS team_applications (
        id TEXT PRIMARY KEY, team_id TEXT NOT NULL REFERENCES teams(id),
        user_id TEXT NOT NULL REFERENCES users(id), status TEXT NOT NULL
          CHECK(status IN ('PENDING','ACCEPTED','REJECTED','CANCELLED')),
        offline_confirmed INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
      CREATE UNIQUE INDEX IF NOT EXISTS team_application_pending ON team_applications(team_id,user_id) WHERE status='PENDING';
      CREATE TABLE IF NOT EXISTS team_bans (
        team_id TEXT REFERENCES teams(id), user_id TEXT REFERENCES users(id), PRIMARY KEY(team_id,user_id));
      CREATE TABLE IF NOT EXISTS team_avoidances (
        user_id TEXT REFERENCES users(id), avoided_id TEXT REFERENCES users(id), PRIMARY KEY(user_id,avoided_id));
      CREATE TABLE IF NOT EXISTS team_availability (
        user_id TEXT REFERENCES users(id), round_id TEXT REFERENCES group_rounds(id),
        week TEXT NOT NULL, slots TEXT NOT NULL, PRIMARY KEY(user_id,round_id));
      CREATE TABLE IF NOT EXISTS team_feedback (
        team_id TEXT REFERENCES teams(id), user_id TEXT REFERENCES users(id),
        consent INTEGER NOT NULL DEFAULT 0, answers TEXT,
        PRIMARY KEY(team_id,user_id));
      INSERT OR IGNORE INTO team_default_rounds(offering_id,round_id)
        SELECT DISTINCT offering_id, (SELECT g.id FROM group_rounds g
          WHERE g.offering_id=outer_round.offering_id
          ORDER BY (SELECT COUNT(*) FROM teams t WHERE t.round_id=g.id AND t.completed=0) DESC,
            (SELECT COUNT(*) FROM team_preferences p WHERE p.round_id=g.id) DESC,g.created,g.id LIMIT 1)
        FROM group_rounds outer_round;
    ''')


def route(db, user, method, path, query, body, error, bounded):
    if not path.startswith('/v1/team-'):
        return NOT_HANDLED
    uid = user['id']
    groups = {}
    def fail(status, code, message):
        raise error(status, message, code)
    def boolean(value, name):
        if type(value) is not bool:
            fail(400, 'INVALID_INPUT', f'{name}应为明确的是或否。')
        return value
    def own_fields(allowed):
        if set(body) - set(allowed):
            fail(400, 'INVALID_INPUT', '请求包含不支持的字段；身份由登录令牌确定。')
    def one(sql, args=()):
        return db.execute(sql, args).fetchone()
    def offering(offering_id):
        if not one('SELECT 1 FROM rooms WHERE id=?', (offering_id,)):
            fail(404, 'OFFERING_NOT_FOUND', '教学班不存在。')
        if not one('SELECT 1 FROM team_consents WHERE user_id=? AND offering_id=?', (uid, offering_id)):
            fail(403, 'CONSENT_REQUIRED', '请先确认所属教学班并同意参与课程组队。')
    def group(round_id):
        if round_id in groups:
            return groups[round_id]
        row = one('SELECT * FROM group_rounds WHERE id=?', (round_id,))
        if not row:
            fail(404, 'ROUND_NOT_FOUND', '组队活动不存在。')
        offering(row['offering_id'])
        groups[round_id] = row
        return row
    def team(team_id, leader=False):
        row = one('SELECT * FROM teams WHERE id=?', (team_id,))
        if not row:
            fail(404, 'TEAM_NOT_FOUND', '团队不存在。')
        group(row['round_id'])
        if leader and row['leader_id'] != uid:
            fail(403, 'LEADER_REQUIRED', '只有团队负责人可以操作。')
        if not row['published'] and row['leader_id'] != uid:
            fail(404, 'TEAM_NOT_FOUND', '团队不存在。')
        return row
    def effective(person, round_id, complete=False):
        p = one('SELECT answers FROM team_profiles WHERE user_id=?', (person,))
        r = one('SELECT answers,overrides FROM team_preferences WHERE user_id=? AND round_id=?', (person, round_id))
        answers = dict(json.loads(p[0]) if p else {}, **(json.loads(r[0]) if r else {}))
        if r:
            answers.update(json.loads(r[1]))
        if complete:
            try:
                validate_answers(answers, complete=True)
            except ValueError:
                fail(409, 'QUESTIONNAIRE_REQUIRED', '请先完成个人画像和本次任务的三道问题。')
        return answers
    def members(row):
        return db.execute('SELECT m.user_id,u.name,u.avatar_version FROM team_members m JOIN users u ON u.id=m.user_id WHERE m.team_id=? ORDER BY m.joined,m.user_id', (row['id'],)).fetchall()
    def joined_course(person, rid):
        return one('SELECT 1 FROM team_members m JOIN group_rounds g ON g.id=m.round_id WHERE m.user_id=? AND g.offering_id=? LIMIT 1', (person, group(rid)['offering_id'])) is not None
    def model(row, member_rows=None):
        mm = members(row) if member_rows is None else member_rows
        return {'id': row['id'], 'roundId': row['round_id'], 'offeringId': group(row['round_id'])['offering_id'], 'name': row['name'],
                'capacity': row['capacity'], 'collaborationMode': row['mode'],
                'mustMeetOffline': bool(row['offline']), 'needsMeeting': bool(row['needs_meeting']),
                'requiredSkills': json.loads(row['skills']), 'requiredRoles': json.loads(row['roles']),
                'description': row['description'], 'status': row['status'], 'published': bool(row['published']),
                'completed': bool(row['completed']), 'version': row['version'], 'created': row['created'],
                'leaderId': row['leader_id'], 'memberCount': len(mm),
                'members': [{'id': m['user_id'], 'name': m['name'], 'avatarVersion': m['avatar_version']} for m in mm],
                'mine': any(m['user_id'] == uid for m in mm), 'manager': row['leader_id'] == uid}
    def eligible(row, person, mm, offline=False, already=None, cache=None):
        if row['status'] == 'FULL' or len(mm) >= row['capacity']:
            return 'TEAM_FULL', '团队名额已满。'
        if row['status'] != 'RECRUITING' or not row['published'] or row['completed']:
            return 'TEAM_CLOSED', '团队已停止招募。'
        if any(m['user_id'] == person for m in mm):
            return 'ALREADY_JOINED', '你已在此团队中。'
        if already is None:
            already = joined_course(person, row['round_id'])
        if already:
            return 'ONE_TEAM_PER_ROUND', '同一课程只能加入一个团队。'
        if row['offline'] and not offline:
            return 'OFFLINE_CONFIRMATION_REQUIRED', '此团队要求线下见面，请主动确认可以参加。'
        if cache is not None:
            if row['id'] in cache['banned'] or any(m['user_id'] in cache['avoided'] for m in mm):
                return 'TEAM_UNAVAILABLE', '暂时无法加入此团队。'
        else:
            room = one('SELECT offering_id FROM group_rounds WHERE id=?', (row['round_id'],))[0]
            if not one('SELECT 1 FROM team_consents WHERE user_id=? AND offering_id=?', (person, room)):
                return 'CONSENT_REQUIRED', '对方尚未同意参与本教学班组队。'
            if one('SELECT 1 FROM team_bans WHERE team_id=? AND user_id=?', (row['id'], person)):
                return 'TEAM_UNAVAILABLE', '暂时无法加入此团队。'
            for m in mm:
                if one('SELECT 1 FROM team_avoidances WHERE (user_id=? AND avoided_id=?) OR (user_id=? AND avoided_id=?)',
                       (person, m['user_id'], m['user_id'], person)):
                    return 'TEAM_UNAVAILABLE', '暂时无法加入此团队。'
        return None
    def refresh_status(row):
        count = one('SELECT COUNT(*) FROM team_members WHERE team_id=?', (row['id'],))[0]
        status = 'CLOSED' if not count or row['status'] == 'CLOSED' else ('FULL' if count >= row['capacity'] else 'RECRUITING')
        db.execute('UPDATE teams SET status=?,version=version+1 WHERE id=?', (status, row['id']))
    def dump(value):
        return json.dumps(value, ensure_ascii=False, allow_nan=False)
    def default_round(oid):
        existing = one('SELECT g.id,g.name,g.created FROM team_default_rounds d JOIN group_rounds g ON g.id=d.round_id WHERE d.offering_id=?', (oid,))
        if existing:
            return dict(existing)
        rid, now = secrets.token_hex(16), int(time.time())
        name = '课程组队'
        db.execute('INSERT INTO group_rounds VALUES (?,?,?,?,?)', (rid, oid, name, uid, now))
        db.execute('INSERT INTO team_default_rounds VALUES (?,?)', (oid, rid))
        return {'id': rid, 'name': name, 'created': now}

    if method not in ('GET', 'POST', 'PUT', 'DELETE'):
        fail(405, 'METHOD_NOT_ALLOWED', '请求方法不支持。')
    if method != 'GET':
        # Serializes all decisions and changes across connections/processes.
        db.execute('BEGIN IMMEDIATE')
    else:
        db.execute('BEGIN')  # Consistent recommendation snapshot under WAL.
    parts = path.strip('/').split('/')
    if path == '/v1/team-config' and method == 'GET':
        return {'config': CONFIG}
    if path == '/v1/team-consent' and method == 'POST':
        own_fields(['offeringId', 'consent', 'confirmMembership'])
        oid = body.get('offeringId')
        if body.get('consent') is not True or body.get('confirmMembership') is not True:
            fail(400, 'CONSENT_REQUIRED', '请主动确认所属教学班并同意组队。')
        if not one('SELECT 1 FROM rooms WHERE id=?', (oid,)):
            fail(404, 'OFFERING_NOT_FOUND', '教学班不存在。')
        db.execute('INSERT OR IGNORE INTO team_consents VALUES (?,?,?)', (uid, oid, int(time.time())))
        return {'ok': True}
    if path == '/v1/team-profile':
        if method == 'GET':
            row = one('SELECT * FROM team_profiles WHERE user_id=?', (uid,))
            return {'answers': json.loads(row['answers']) if row else {}, 'tags': json.loads(row['tags']) if row else {},
                    'questionnaireVersion': row['version'] if row else CONFIG['questionnaireVersion']}
        if method in ('POST', 'PUT'):
            own_fields(['answers', 'tags', 'questionnaireVersion'])
            if type(body.get('questionnaireVersion')) is not int or body['questionnaireVersion'] != CONFIG['questionnaireVersion']:
                fail(409, 'VERSION_MISMATCH', '问卷版本已更新，请刷新。')
            answers = validate_answers(body.get('answers'), scope='profile', complete=True)
            tags = body.get('tags', {})
            if not isinstance(tags, dict) or set(tags) - CONFIG['optionalTags'].keys() or any(v not in CONFIG['optionalTags'][k] for k, v in tags.items()):
                fail(400, 'INVALID_INPUT', '可选标签无效。')
            db.execute('INSERT INTO team_profiles VALUES (?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET answers=excluded.answers,version=excluded.version,tags=excluded.tags',
                       (uid, dump(answers), CONFIG['questionnaireVersion'], dump(tags)))
            return {'ok': True}
    if path == '/v1/team-default-round' and method == 'POST':
        own_fields(['offeringId'])
        oid = body.get('offeringId')
        offering(oid)
        return {'round': default_round(oid)}
    if path == '/v1/team-rounds':
        oid = body.get('offeringId') if method == 'POST' else query.get('offeringId', [''])[0]
        offering(oid)
        if method == 'GET':
            rows = db.execute('SELECT g.id,g.name,g.created FROM group_rounds g JOIN team_default_rounds d ON d.round_id=g.id WHERE d.offering_id=?', (oid,)).fetchall()
            return {'rounds': [dict(row) for row in rows]}
        if method == 'POST':
            own_fields(['offeringId', 'name'])
            # Legacy clients receive the same course scope, never a new activity.
            return default_round(oid)
    if len(parts) == 3 and parts[1] == 'team-preferences':
        rid = parts[2]
        group(rid)
        if method == 'GET':
            row = one('SELECT * FROM team_preferences WHERE user_id=? AND round_id=?', (uid, rid))
            return {'answers': json.loads(row['answers']) if row else {}, 'overrides': json.loads(row['overrides']) if row else {},
                    'canMeetOffline': bool(row['can_meet_offline']) if row else False, 'willingInvites': bool(row['willing_invites']) if row else False}
        if method in ('POST', 'PUT'):
            own_fields(['answers', 'overrides', 'canMeetOffline', 'willingInvites', 'questionnaireVersion'])
            if type(body.get('questionnaireVersion')) is not int or body['questionnaireVersion'] != CONFIG['questionnaireVersion']:
                fail(409, 'VERSION_MISMATCH', '问卷版本已更新，请刷新。')
            answers = validate_answers(body.get('answers'), scope='round', complete=True)
            overrides = body.get('overrides', {})
            if not isinstance(overrides, dict) or set(overrides) - {'q3', 'q4'}:
                fail(400, 'INVALID_INPUT', '本次任务只能覆盖技能和角色偏好。')
            validate_answers(overrides)
            offline = boolean(body.get('canMeetOffline', False), '线下意愿')
            invites = boolean(body.get('willingInvites', False), '邀请意愿')
            db.execute('INSERT INTO team_preferences VALUES (?,?,?,?,?,?,?) ON CONFLICT(user_id,round_id) DO UPDATE SET answers=excluded.answers,overrides=excluded.overrides,can_meet_offline=excluded.can_meet_offline,willing_invites=excluded.willing_invites,version=excluded.version',
                       (uid, rid, dump(answers), dump(overrides), offline, invites, CONFIG['questionnaireVersion']))
            return {'ok': True}
    if path == '/v1/team-list':
        rid = body.get('roundId') if method == 'POST' else query.get('roundId', [''])[0]
        group(rid)
        if method == 'POST':
            own_fields(['roundId', 'name', 'capacity', 'collaborationMode', 'mustMeetOffline', 'needsMeeting', 'requiredSkills', 'requiredRoles', 'description', 'publish'])
            if not one('SELECT 1 FROM team_default_rounds WHERE round_id=?', (rid,)):
                fail(409, 'DEFAULT_ROUND_REQUIRED', '请从课程组队主页创建团队。')
            capacity = body.get('capacity', CONFIG['limits']['defaultCapacity'])
            if type(capacity) is not int or not 2 <= capacity <= CONFIG['limits']['maxCapacity']:
                fail(400, 'INVALID_INPUT', '团队容量应为 2–12 人。')
            mode = body.get('collaborationMode')
            if mode not in CONFIG['baseWeights']:
                fail(400, 'INVALID_INPUT', '请选择合作模式。')
            if joined_course(uid, rid):
                fail(409, 'ONE_TEAM_PER_ROUND', '你已加入这门课程的团队。')
            if one('SELECT COUNT(*) FROM teams WHERE round_id=?', (rid,))[0] >= CONFIG['limits']['maxTeamsPerRound']:
                fail(409, 'TEAM_LIMIT', '本次活动团队数量已达上限。')
            published = boolean(body.get('publish', True), '发布状态')
            if published:
                effective(uid, rid, complete=True)
            tid, now = secrets.token_hex(16), int(time.time())
            offline, meeting = boolean(body.get('mustMeetOffline', False), '线下要求'), boolean(body.get('needsMeeting', False), '会议需求')
            skills, roles = validate_requirements(body.get('requiredSkills', []), 'skill'), validate_requirements(body.get('requiredRoles', []), 'role')
            if any(requirement['count'] > capacity for requirement in skills + roles):
                fail(400, 'INVALID_INPUT', '单项需求人数不能超过团队容量。')
            preference = one('SELECT can_meet_offline FROM team_preferences WHERE user_id=? AND round_id=?', (uid, rid))
            if offline and not (preference and preference[0]):
                fail(409, 'OFFLINE_CONFIRMATION_REQUIRED', '请先在本次任务偏好中确认可以线下参加。')
            db.execute('INSERT INTO teams VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                       (tid, rid, uid, bounded(body.get('name'), '团队名称', 80), capacity, mode, offline, meeting,
                        dump(skills), dump(roles), bounded(body.get('description', ''), '团队说明', 1000, False),
                        'RECRUITING' if published else 'CLOSED', published, 0, 1, now))
            db.execute('INSERT INTO team_members VALUES (?,?,?,?)', (tid, uid, rid, now))
            return {'team': model(team(tid))}
        if method == 'GET':
            view = query.get('view', [''])[0]
            if view not in ('', 'recruiting', 'mine'):
                fail(400, 'INVALID_INPUT', '组队列表类型无效。')
            # One batch for teams, memberships, profiles and preferences (no questionnaire N+1).
            if view == 'mine':
                rows = db.execute('''SELECT t.* FROM teams t JOIN group_rounds g ON g.id=t.round_id
                    JOIN team_members own ON own.team_id=t.id WHERE g.offering_id=? AND own.user_id=?''',
                                  (group(rid)['offering_id'], uid)).fetchall()
            else:
                rows = db.execute('SELECT * FROM teams WHERE round_id=? AND (published=1 OR leader_id=?) LIMIT ?', (rid, uid, CONFIG['limits']['maxTeamsPerRound'])).fetchall()
            all_members = db.execute('SELECT m.team_id,m.user_id,u.name,u.avatar_version,p.answers profile,r.answers preference,r.overrides FROM team_members m JOIN users u ON u.id=m.user_id JOIN group_rounds g ON g.id=m.round_id LEFT JOIN team_profiles p ON p.user_id=m.user_id LEFT JOIN team_preferences r ON r.user_id=m.user_id AND r.round_id=m.round_id WHERE g.offering_id=?', (group(rid)['offering_id'],)).fetchall()
            grouped = {}
            answers = {}
            for m in all_members:
                grouped.setdefault(m['team_id'], []).append(m)
                answers[m['user_id']] = dict(json.loads(m['profile'] or '{}'), **json.loads(m['preference'] or '{}'))
                answers[m['user_id']].update(json.loads(m['overrides'] or '{}'))
            candidate = effective(uid, rid)
            pref = one('SELECT can_meet_offline FROM team_preferences WHERE user_id=? AND round_id=?', (uid, rid))
            joined = joined_course(uid, rid)
            recommendations = not view and query.get('recommend', ['false'])[0] == 'true'
            cache = {'banned': {r[0] for r in db.execute('SELECT team_id FROM team_bans WHERE user_id=?', (uid,))},
                     'avoided': {r[0] for r in db.execute('SELECT avoided_id FROM team_avoidances WHERE user_id=? UNION SELECT user_id FROM team_avoidances WHERE avoided_id=?', (uid, uid))}}
            result = []
            for row in rows:
                mm = grouped.get(row['id'], [])
                if view == 'recruiting':
                    if not row['published'] or row['completed'] or row['status'] != 'RECRUITING' or len(mm) >= row['capacity'] or any(m['user_id'] == uid for m in mm):
                        continue
                    if row['id'] in cache['banned'] or any(m['user_id'] in cache['avoided'] for m in mm):
                        continue
                if recommendations and eligible(row, uid, mm, bool(pref and pref[0]), joined, cache):
                    continue
                item = model(row, mm)
                mode_filter = query.get('mode', [''])[0]
                skill_filter = query.get('skill', [''])[0]
                if mode_filter and item['collaborationMode'] != mode_filter:
                    continue
                if skill_filter and not any(r['tag'] == skill_filter for r in item['requiredSkills']):
                    continue
                if recommendations or view == 'recruiting':
                    item['match'] = match_team(candidate, [answers[m['user_id']] for m in mm], item)
                result.append(item)
            result.sort(key=lambda t: (-(t.get('match', {}).get('displayScore') or -1),
                                       -(t.get('match', {}).get('score') or -1), -t['created'], t['id']))
            limit = max(1, min(int(query.get('limit', [CONFIG['limits']['pageSize']])[0]), CONFIG['limits']['maxPageSize']))
            offset = max(0, min(int(query.get('offset', [0])[0]), CONFIG['limits']['maxTeamsPerRound']))
            return {'teams': result[offset:offset + limit], 'next': offset + limit if len(result) > offset + limit else None}
    if path == '/v1/team-avoidances':
        if method == 'GET':
            return {'users': [dict(r) for r in db.execute('SELECT u.id,u.name FROM team_avoidances a JOIN users u ON u.id=a.avoided_id WHERE a.user_id=?', (uid,))]}
        if method in ('POST', 'DELETE'):
            own_fields(['userId'])
            other = body.get('userId')
            if other == uid or not one('SELECT 1 FROM users WHERE id=?', (other,)):
                fail(400, 'INVALID_INPUT', '请选择其他已存在的组队成员。')
            if method == 'POST':
                db.execute('INSERT OR IGNORE INTO team_avoidances VALUES (?,?)', (uid, other))
            else:
                db.execute('DELETE FROM team_avoidances WHERE user_id=? AND avoided_id=?', (uid, other))
            return {'ok': True}
    if len(parts) >= 3 and parts[1] == 'team-detail':
        row = team(parts[2])
        action = parts[3] if len(parts) == 4 else ''
        if not action and method == 'GET':
            return {'team': model(row)}
        if action in ('publish', 'close', 'complete') and method == 'POST':
            own_fields([])
            team(row['id'], leader=True)
            if row['completed']:
                fail(409, 'TEAM_COMPLETED', '本次合作已结束。')
            if action == 'publish':
                effective(uid, row['round_id'], complete=True)
                if not members(row):
                    fail(409, 'TEAM_HAS_NO_MEMBERS', '空团队不能招募。')
                db.execute("UPDATE teams SET published=1,status=CASE WHEN capacity<=(SELECT COUNT(*) FROM team_members WHERE team_id=teams.id) THEN 'FULL' ELSE 'RECRUITING' END,version=version+1 WHERE id=?", (row['id'],))
            else:
                db.execute("UPDATE teams SET status='CLOSED',completed=?,version=version+1 WHERE id=?", (action == 'complete', row['id']))
                db.execute("UPDATE team_applications SET status='CANCELLED' WHERE team_id=? AND status='PENDING'", (row['id'],))
                if action == 'complete':
                    db.execute('INSERT OR IGNORE INTO team_feedback(team_id,user_id) SELECT team_id,user_id FROM team_members WHERE team_id=?', (row['id'],))
            return {'ok': True}
        if action in ('leave', 'remove') and method == 'POST':
            own_fields(['userId'] if action == 'remove' else [])
            if row['completed']:
                fail(409, 'TEAM_COMPLETED', '合作已结束，成员名单用于匿名反馈，不能再修改。')
            person = uid if action == 'leave' else body.get('userId')
            if action == 'remove':
                team(row['id'], leader=True)
                if person == uid:
                    fail(400, 'INVALID_INPUT', '退出请使用退出团队。')
            if not one('SELECT 1 FROM team_members WHERE team_id=? AND user_id=?', (row['id'], person)):
                fail(404, 'MEMBER_NOT_FOUND', '成员不存在。')
            db.execute('DELETE FROM team_members WHERE team_id=? AND user_id=?', (row['id'], person))
            if action == 'remove':
                db.execute('INSERT OR IGNORE INTO team_bans VALUES (?,?)', (row['id'], person))
            elif row['leader_id'] == person:
                successor = one('SELECT user_id FROM team_members WHERE team_id=? ORDER BY joined,user_id LIMIT 1', (row['id'],))
                if successor:
                    db.execute('UPDATE teams SET leader_id=? WHERE id=?', (successor[0], row['id']))
                else:
                    db.execute('UPDATE teams SET published=0 WHERE id=?', (row['id'],))
            refresh_status(row)
            return {'ok': True}
        if action == 'apply' and method == 'POST':
            own_fields(['offlineConfirmed'])
            confirm = boolean(body.get('offlineConfirmed', False), '线下确认')
            blocked = eligible(row, uid, members(row), confirm)
            if blocked:
                fail(409, *blocked)
            effective(uid, row['round_id'], complete=True)
            if one("SELECT 1 FROM team_applications WHERE team_id=? AND user_id=? AND status='PENDING'", (row['id'], uid)):
                fail(409, 'APPLICATION_PENDING', '已有申请待审核。')
            aid = secrets.token_hex(16)
            db.execute('INSERT INTO team_applications VALUES (?,?,?,?,?,?)', (aid, row['id'], uid, 'PENDING', confirm, int(time.time())))
            return {'id': aid}
        if action == 'applications' and method == 'GET':
            sql = 'SELECT a.id,a.user_id,a.status,a.created,u.name FROM team_applications a JOIN users u ON u.id=a.user_id WHERE a.team_id=?'
            args = [row['id']]
            if row['leader_id'] != uid:
                sql += ' AND a.user_id=?'
                args.append(uid)
            sql += " ORDER BY a.created DESC,a.id LIMIT 100"
            return {'applications': [dict(r) for r in db.execute(sql, args)]}
        if action == 'feedback' :
            mine = one('SELECT * FROM team_feedback WHERE team_id=? AND user_id=?', (row['id'], uid))
            if not row['completed'] or not mine:
                fail(403, 'FEEDBACK_UNAVAILABLE', '只有已结束合作的参与成员可以反馈。')
            participants = db.execute('SELECT consent,answers FROM team_feedback WHERE team_id=?', (row['id'],)).fetchall()
            all_consent = len(participants) >= 2 and all(p['consent'] for p in participants)
            if method == 'GET':
                aggregate = None
                if all_consent and all(p['answers'] for p in participants):
                    aa = [json.loads(p['answers']) for p in participants]
                    aggregate = {'satisfaction': round(sum(a['satisfaction'] for a in aa) / len(aa), 1),
                                 'efficiency': round(sum(a['efficiency'] for a in aa) / len(aa), 1),
                                 'willingAgain': round(sum(a['willingAgain'] for a in aa) / len(aa), 2)}
                return {'consent': bool(mine['consent']), 'allConsented': all_consent,
                        'answers': json.loads(mine['answers']) if mine['answers'] else None, 'aggregate': aggregate}
            if method == 'POST':
                own_fields(['consent', 'answers'])
                consent = boolean(body.get('consent'), '反馈同意')
                if not consent:
                    db.execute('UPDATE team_feedback SET consent=0,answers=NULL WHERE team_id=? AND user_id=?', (row['id'], uid))
                    return {'ok': True}
                answers = body.get('answers')
                if answers is not None:
                    if not all_consent:
                        fail(409, 'ALL_CONSENT_REQUIRED', '所有参与成员同意匿名汇总后，才能收集反馈。')
                    if not isinstance(answers, dict) or set(answers) != {'satisfaction', 'efficiency', 'willingAgain'} or any(type(answers[k]) is not int or not 1 <= answers[k] <= 5 for k in ('satisfaction', 'efficiency')) or type(answers['willingAgain']) is not bool:
                        fail(400, 'INVALID_INPUT', '反馈评分应为 1–5，再次合作意愿应为是或否。')
                db.execute('UPDATE team_feedback SET consent=1,answers=? WHERE team_id=? AND user_id=?', (dump(answers) if answers else None, row['id'], uid))
                return {'ok': True}
        if action == 'meeting-times' and method == 'GET':
            if row['completed']:
                fail(409, 'TEAM_COMPLETED', '本次合作已结束，不再提供会议时间建议。')
            if not row['offline'] and not row['needs_meeting']:
                return {'slots': [], 'message': '此任务未声明共同会议需求。'}
            mm = members(row)
            # Only members and a candidate who opted in may request derived common slots.
            ids = [m['user_id'] for m in mm]
            if uid not in ids:
                preference = one('SELECT can_meet_offline FROM team_preferences WHERE user_id=? AND round_id=?', (uid, row['round_id']))
                blocked = eligible(row, uid, mm, bool(preference and preference[0]))
                if blocked:
                    fail(409, *blocked)
                ids.append(uid)
            available = db.execute('SELECT user_id,week,slots FROM team_availability WHERE round_id=?', (row['round_id'],)).fetchall()
            selected = {r['user_id']: r for r in available if r['user_id'] in ids}
            if len(selected) != len(ids) or len({r['week'] for r in selected.values()}) != 1:
                return {'slots': [], 'message': '所有参与者主动提供同一周的空闲时间后，才显示共同时间。'}
            slots = set.intersection(*(set(json.loads(r['slots'])) for r in selected.values()))
            return {'slots': sorted(slots), 'week': next(iter(selected.values()))['week'], 'message': '仅供会议时间建议，不参与规则匹配分。'}
    if len(parts) == 3 and parts[1] == 'team-availability':
        rid = parts[2]
        group(rid)
        if method == 'GET':
            row = one('SELECT week,slots FROM team_availability WHERE user_id=? AND round_id=?', (uid, rid))
            return {'week': row['week'] if row else None, 'slots': json.loads(row['slots']) if row else [], 'consent': row is not None}
        if method == 'DELETE':
            db.execute('DELETE FROM team_availability WHERE user_id=? AND round_id=?', (uid, rid))
            return {'ok': True}
        if method in ('POST', 'PUT'):
            own_fields(['consent', 'week', 'slots'])
            if not one('SELECT 1 FROM teams WHERE round_id=? AND completed=0 AND (offline=1 OR needs_meeting=1) AND (published=1 OR leader_id=?)', (rid, uid)):
                fail(409, 'MEETING_NOT_REQUIRED', '本次活动尚无需要会面的任务，不启用空闲时间分享。')
            if body.get('consent') is not True:
                fail(400, 'CONSENT_REQUIRED', '需要主动同意分享抽象空闲时段。')
            week = body.get('week')
            try:
                date = datetime.date.fromisoformat(week)
                if date.weekday() != 0 or date.isoformat() != week:
                    raise ValueError()
            except (ValueError, TypeError):
                fail(400, 'INVALID_INPUT', '请选择星期一作为时间表起始日期。')
            slots = body.get('slots')
            if not isinstance(slots, list) or len(slots) > 336 or any(type(s) is not int or not 0 <= s < 336 for s in slots) or len(set(slots)) != len(slots):
                fail(400, 'INVALID_INPUT', '空闲时段无效。')
            db.execute('INSERT INTO team_availability VALUES (?,?,?,?) ON CONFLICT(user_id,round_id) DO UPDATE SET week=excluded.week,slots=excluded.slots', (uid, rid, week, dump(sorted(slots))))
            return {'ok': True}
    if len(parts) == 3 and parts[1] == 'team-applications':
        application = one('SELECT * FROM team_applications WHERE id=?', (parts[2],))
        if not application:
            fail(404, 'APPLICATION_NOT_FOUND', '申请不存在。')
        row = team(application['team_id'])
        if method == 'POST':
            own_fields(['action'])
            action = body.get('action')
            if action == 'cancel':
                if application['user_id'] != uid:
                    fail(403, 'APPLICANT_REQUIRED', '只能取消自己的申请。')
            elif action in ('accept', 'reject'):
                team(row['id'], leader=True)
            else:
                fail(400, 'INVALID_INPUT', '申请操作无效。')
            if application['status'] != 'PENDING':
                fail(409, 'APPLICATION_RESOLVED', '此申请已经处理。')
            if action == 'accept':
                blocked = eligible(row, application['user_id'], members(row), bool(application['offline_confirmed']))
                if blocked:
                    fail(409, *blocked)
                effective(application['user_id'], row['round_id'], complete=True)
                db.execute('INSERT INTO team_members VALUES (?,?,?,?)', (row['id'], application['user_id'], row['round_id'], int(time.time())))
                refresh_status(row)
                db.execute("UPDATE team_applications SET status='CANCELLED' WHERE user_id=? AND status='PENDING' AND id!=? AND team_id IN (SELECT id FROM teams WHERE round_id=?)", (application['user_id'], application['id'], row['round_id']))
            db.execute('UPDATE team_applications SET status=? WHERE id=?', ({'accept': 'ACCEPTED', 'reject': 'REJECTED', 'cancel': 'CANCELLED'}[action], application['id']))
            return {'ok': True}
    fail(404, 'NOT_FOUND', '组队接口不存在。')
