import json
import math
from pathlib import Path


def validate_config(config):
    questions = {q['id']: q for q in config['questions']}
    if len(questions) != 10 or set(questions) != {f'q{i}' for i in range(1, 11)}:
        raise ValueError('Question configuration must contain ten unique questions')
    if set(config['matrices']) != {'q1', 'q2', 'q5', 'q6', 'q7', 'q8'}:
        raise ValueError('Exactly six compatibility matrices are required')
    for key, question in questions.items():
        options = [v['id'] for v in question['options']]
        if not options or len(set(options)) != len(options) or any(not v.startswith(key.upper() + '_') for v in options):
            raise ValueError('Invalid question options')
        if not 1 <= question['min'] <= question['max'] <= len(options) or not set(question['exclusive']).issubset(options):
            raise ValueError('Invalid answer cardinality')
    if set(config['baseWeights']) != {'LIGHT', 'STAGED', 'DEEP'} or set(config['communicationWeights']) != set(config['baseWeights']):
        raise ValueError('Invalid collaboration modes')
    if any(set(w) != {'G', 'T', 'C', 'K'} for w in config['baseWeights'].values()):
        raise ValueError('Invalid scoring dimensions')
    for key, matrix in config['matrices'].items():
        options = {v['id'] for v in questions[key]['options']}
        if set(matrix) != options:
            raise ValueError('Incomplete matrix')
        for left, row in matrix.items():
            if set(row) != options:
                raise ValueError('Incomplete matrix row')
            for right, value in row.items():
                if not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 1:
                    raise ValueError('Invalid matrix value')
                if value != matrix[right][left]:
                    raise ValueError('Asymmetric matrix')
    for weights in [*config['baseWeights'].values(), *config['communicationWeights'].values(),
                    config['goalWeights'], config['aggregation'], config['skillRoleWeights']]:
        if any(not math.isfinite(w) or w < 0 for w in weights.values()) or not math.isclose(sum(weights.values()), 1):
            raise ValueError('Invalid weights')
    if any(w.get('q9', 0) != 0 for w in config['communicationWeights'].values()):
        raise ValueError('Q9 must never be scored')
    if any(set(w) - {'q6', 'q7', 'q8', 'q9'} for w in config['communicationWeights'].values()):
        raise ValueError('Invalid communication question')
    if set(config['preferenceBoosts']) != {'Q10_B', 'Q10_C', 'Q10_D'}:
        raise ValueError('Only documented Q10 preferences may change weights')
    for value in config['preferenceBoosts'].values():
        if value['dimension'] not in {'G', 'K', 'C'} or not math.isfinite(value['amount']) or value['amount'] < 0:
            raise ValueError('Invalid preference boost')
    for value in [config['confidenceThreshold'], *config['reasonThresholds'].values(), config['flexibleRole']['fit']]:
        if not math.isfinite(value) or not 0 <= value <= 1:
            raise ValueError('Invalid product threshold')
    return config


CONFIG = validate_config(json.loads((Path(__file__).parent / 'config/rule-v1.0.json').read_text(encoding='utf-8')))


def validate_answers(answers, scope=None, complete=False, config=CONFIG):
    if not isinstance(answers, dict):
        raise ValueError('问卷应为答案对象。')
    questions = {q['id']: q for q in config['questions'] if scope is None or q['scope'] == scope}
    if set(answers) - questions.keys() or (complete and set(answers) != questions.keys()):
        raise ValueError('问卷题目不完整或不属于当前问卷。')
    for key, value in answers.items():
        question = questions[key]
        values = value if question['multiple'] else [value]
        if not isinstance(values, list) or any(not isinstance(v, str) for v in values):
            raise ValueError('问卷选项格式无效。')
        if not question['min'] <= len(values) <= question['max'] or len(set(values)) != len(values):
            raise ValueError('问卷选项数量无效或重复。')
        if set(values) - {v['id'] for v in question['options']}:
            raise ValueError('问卷包含无效选项。')
        if len(values) > 1 and set(values).intersection(question['exclusive']):
            raise ValueError('“暂无明确特长”不能与其他技能同时选择。')
    return dict(answers)


def validate_requirements(values, kind, config=CONFIG):
    question = next(q for q in config['questions'] if q['id'] == ('q3' if kind == 'skill' else 'q4'))
    excluded = config['emptySkills'] if kind == 'skill' else config['flexibleRole']['answer']
    allowed = {o['id'] for o in question['options']} - {excluded}
    if not isinstance(values, list) or len(values) > len(allowed):
        raise ValueError('团队需求格式无效。')
    seen, result = set(), []
    for item in values:
        if not isinstance(item, dict) or set(item) - {'tag', 'count', 'weight'}:
            raise ValueError('团队需求字段无效。')
        tag, count, weight = item.get('tag'), item.get('count'), item.get('weight', 1)
        if not isinstance(tag, str) or tag not in allowed or tag in seen or type(count) is not int or not 1 <= count <= config['limits']['maxCapacity']:
            raise ValueError('团队需求标签或人数无效。')
        if type(weight) not in (int, float) or not math.isfinite(weight) or not 0 < weight <= 100:
            raise ValueError('团队需求权重应为正数。')
        seen.add(tag)
        result.append({'tag': tag, 'count': count, 'weight': weight})
    return result


def clamp(value):
    if not math.isfinite(value):
        raise ValueError('Non-finite score')
    return min(1., max(0., value))


def weighted_available(parts):
    used = [(value, weight) for value, weight in parts if value is not None and weight > 0]
    return clamp(sum(clamp(v) * w for v, w in used) / sum(w for _, w in used)) if used else None


def lookup(matrix, left=None, right=None):
    return None if left is None or right is None else clamp(matrix[left][right])


def pair_dimensions(a, b, mode, config=CONFIG):
    def pair(key):
        return lookup(config['matrices'][key], a.get(key), b.get(key))
    return {'G': weighted_available([(pair(q), w) for q, w in config['goalWeights'].items()]),
            'T': pair('q5'),
            'C': weighted_available([(pair(q), w) for q, w in config['communicationWeights'][mode].items() if w > 0])}


def aggregate_to_team(values, config=CONFIG):
    used = [clamp(value) for value in values if value is not None]
    if not used:
        return None
    weights = config['aggregation']
    return clamp(weights['mean'] * sum(used) / len(used) + weights['minimum'] * min(used))


def unmet(requirements, members, key):
    return [(r, max(r['count'] - sum(r['tag'] in (m.get(key, []) if key == 'q3' else [m.get(key)]) for m in members), 0))
            for r in requirements]


def gap_fit(candidate, gaps, key, config=CONFIG):
    gaps = [(r, gap) for r, gap in gaps if gap > 0]
    if not gaps or key not in candidate:
        return None
    def fit(tag):
        if key == 'q3':
            return float(tag in candidate[key])
        if candidate[key] == config['flexibleRole']['answer']:
            return config['flexibleRole']['fit']
        return float(candidate[key] == tag)
    return clamp(sum(r['weight'] * min(gap, 1) * fit(r['tag']) for r, gap in gaps) /
                 sum(r['weight'] * gap for r, gap in gaps))


def match_team(candidate, members, team, config=CONFIG):
    """Hard eligibility is evaluated by the service BEFORE calling this function."""
    validate_answers(candidate, config=config)
    for member in members:
        validate_answers(member, config=config)
    if not members:
        raise ValueError('TEAM_HAS_NO_MEMBERS')
    mode = team['collaborationMode']
    if mode not in config['baseWeights']:
        raise ValueError('Unknown collaboration mode')
    skills = validate_requirements(team.get('requiredSkills', []), 'skill', config)
    roles = validate_requirements(team.get('requiredRoles', []), 'role', config)
    skill_gaps, role_gaps = unmet(skills, members, 'q3'), unmet(roles, members, 'q4')
    applicable = {'skill': any(gap > 0 for _, gap in skill_gaps), 'role': any(gap > 0 for _, gap in role_gaps)}
    pairs = [pair_dimensions(candidate, member, mode, config) for member in members]
    dimensions = {d: aggregate_to_team([p[d] for p in pairs], config) for d in ('G', 'T', 'C')}
    components = {'skill': gap_fit(candidate, skill_gaps, 'q3', config), 'role': gap_fit(candidate, role_gaps, 'q4', config)}
    dimensions['K'] = weighted_available([(components[k], w) for k, w in config['skillRoleWeights'].items()])
    present = lambda q, m: float(q in candidate and q in m)
    completeness = {
        'G': sum(sum(w * present(q, m) for q, w in config['goalWeights'].items()) for m in members) / len(members),
        'T': sum(present('q5', m) for m in members) / len(members),
        'C': sum(sum(w * present(q, m) for q, w in config['communicationWeights'][mode].items()) for m in members) / len(members),
    }
    if any(applicable.values()):
        completeness['K'] = weighted_available([(float(('q3' if k == 'skill' else 'q4') in candidate), w)
                                                for k, w in config['skillRoleWeights'].items() if applicable[k]])
    base = config['baseWeights'][mode]
    confidence = weighted_available([(value, base[d]) for d, value in completeness.items()])
    weights = dict(base)
    for answer in candidate.get('q10', []):
        boost = config['preferenceBoosts'].get(answer)
        if boost and dimensions[boost['dimension']] is not None:
            weights[boost['dimension']] += boost['amount']
    total = weighted_available([(value, weights[d]) for d, value in dimensions.items()])
    score = math.floor(total * 1000 + .5) / 10 if total is not None else None
    display = confidence >= config['confidenceThreshold'] and score is not None
    high, low = config['reasonThresholds']['high'], config['reasonThresholds']['low']
    reasons, cautions = [], []
    for dimension, label in [('G', '任务目标和投入意愿较契合'), ('T', '推进节奏较契合'), ('C', '合作与沟通偏好较契合')]:
        if dimensions[dimension] is not None and dimensions[dimension] >= high:
            reasons.append(label)
    options = {v['id']: v['label'] for q in config['questions'] for v in q['options']}
    hits = [options[r['tag']] for r, gap in skill_gaps if gap > 0 and r['tag'] in candidate.get('q3', [])]
    if hits:
        reasons.insert(0, '你选择了团队尚缺的技能领域：' + '、'.join(hits))
    for dimension, text in [('G', '任务目标和投入意愿可先与团队确认'), ('T', '可先商议推进节奏和截止时间'), ('C', '可先商议合作方式与沟通安排')]:
        if len(reasons) >= 2:
            break
        if dimensions[dimension] is not None and dimensions[dimension] < high:
            reasons.append(text)
    if dimensions['T'] is not None and dimensions['T'] < low:
        cautions.append('推进节奏有差异，建议先约定截止时间。')
    if mode != 'LIGHT' and any(candidate.get('q7') and m.get('q7') and
                             lookup(config['matrices']['q7'], candidate['q7'], m['q7']) < low for m in members):
        cautions.append('同步频率偏好有差异，建议先约定沟通节点。')
    if not display:
        reasons = ['问卷信息不足，请补全后查看匹配']
    return {'score': score, 'displayScore': display, 'confidence': round(confidence, 3),
            'dimensions': dimensions, 'reasons': reasons[:3], 'cautions': cautions[:2],
            'algorithmVersion': config['algorithmVersion']}
