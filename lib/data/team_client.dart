import '../domain/schedule.dart';
import 'discussion_client.dart';

class TeamClient {
  const TeamClient(this.discussion);
  final DiscussionClient discussion;
  String get userId => discussion.userId;
  Future<Json> get(String path, [Map<String, String> query = const {}]) =>
      discussion.request(
        'GET',
        'v1/team-$path${query.isEmpty ? '' : Uri(queryParameters: query)}',
      );
  Future<Json> write(String path, Json body, {String method = 'POST'}) =>
      discussion.request(method, 'v1/team-$path', body: body);
}

/// Form validation uses the server's versioned schema, including exclusive choices.
String? teamAnswerError(Json question, dynamic answer) {
  final values = question['multiple'] == true
      ? (answer is List ? answer : <dynamic>[])
      : (answer is String ? [answer] : <dynamic>[]);
  if (values.length < (question['min'] as int)) return '请完成本题。';
  if (values.length > (question['max'] as int)) {
    return '本题最多选择 ${question['max']} 项。';
  }
  final allowed = (question['options'] as List).map((o) => o['id']).toSet();
  if (values.toSet().length != values.length ||
      values.any((v) => !allowed.contains(v))) {
    return '选项无效或重复。';
  }
  if (values.length > 1 &&
      (question['exclusive'] as List).any(values.contains)) {
    return '“暂无明确特长”不能与其他技能同时选择。';
  }
  return null;
}

List<String> toggleTeamAnswer(
  Json question,
  List<String> current,
  String selected,
) {
  final values = [...current];
  if (values.contains(selected)) {
    values.remove(selected);
  } else if ((question['exclusive'] as List).contains(selected)) {
    return [selected];
  } else {
    values.removeWhere((v) => (question['exclusive'] as List).contains(v));
    if (values.length < (question['max'] as int)) values.add(selected);
  }
  return values;
}
