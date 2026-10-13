import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/discussion_client.dart';
import 'package:seu_timetable/data/team_client.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/domain/team_availability.dart';
import 'package:seu_timetable/ui/team_page.dart';
import 'package:seu_timetable/ui/team_questionnaire.dart';

final config =
    jsonDecode(
          File('server/team_matching/config/rule-v1.0.json').readAsStringSync(),
        )
        as Json;
final questions = (config['questions'] as List).cast<Json>();
Json answersFor(String scope) => {
  for (final q in questions.where((q) => q['scope'] == scope))
    q['id'] as String: q['multiple'] == true
        ? [q['options'][0]['id']]
        : q['options'][0]['id'],
};

class FakeTeamDiscussion extends DiscussionClient {
  FakeTeamDiscussion({this.hasProfile = false, this.hasConsent = true})
    : super(sessionFile: File('unused-team-session'));
  bool hasProfile, hasConsent;
  Json profile = {}, preferences = {};
  final List<(String, Json)> writes = [];
  @override
  Future<Json> request(String method, String path, {Json? body}) async {
    if (method != 'GET') {
      if (path == 'v1/team-default-round') {
        if (!hasConsent) throw const FormatException('请先确认所属教学班并同意参与课程组队。');
        return {
          'round': {'id': 'round-one', 'name': '课程组队'},
        };
      }
      writes.add((path, body ?? {}));
      if (path == 'v1/team-profile') {
        profile = {...body!['answers'] as Json};
        hasProfile = true;
      }
      if (path.startsWith('v1/team-preferences/')) {
        preferences = {...body!['answers'] as Json};
      }
      if (path == 'v1/team-consent') hasConsent = true;
      return {'ok': true};
    }
    if (path == 'v1/team-config') return {'config': config};
    if (path == 'v1/team-profile') {
      return {
        'answers': hasProfile
            ? (profile.isEmpty ? answersFor('profile') : profile)
            : <String, dynamic>{},
        'tags': <String, dynamic>{},
      };
    }
    if (path.startsWith('v1/team-preferences/')) {
      return {
        'answers': preferences,
        'overrides': <String, dynamic>{},
        'canMeetOffline': false,
      };
    }
    if (path.startsWith('v1/team-rounds')) {
      if (!hasConsent) throw const FormatException('请先确认所属教学班并同意参与课程组队。');
      return {
        'rounds': [
          {'id': 'round-one', 'name': '展示任务'},
        ],
      };
    }
    if (path.startsWith('v1/team-list')) {
      if (Uri.parse(path).queryParameters['view'] == 'mine') {
        return {'teams': <Json>[], 'next': null};
      }
      return {
        'teams': [
          {
            'id': 'TEAM-ONE',
            'name': '问卷未补全团队',
            'memberCount': 1,
            'capacity': 4,
            'collaborationMode': 'LIGHT',
            'status': 'RECRUITING',
            'published': true,
            'mine': false,
            'mustMeetOffline': false,
            'match': {
              'displayScore': false,
              'score': 99.9,
              'reasons': ['问卷信息不足，请补全后查看匹配'],
              'cautions': [],
            },
          },
          {
            'id': 'TEAM-TWO',
            'name': '完整问卷团队',
            'memberCount': 2,
            'capacity': 4,
            'collaborationMode': 'LIGHT',
            'status': 'RECRUITING',
            'published': true,
            'mine': false,
            'mustMeetOffline': false,
            'match': {
              'displayScore': true,
              'score': 76.7,
              'reasons': ['任务目标和投入意愿较契合'],
              'cautions': [],
            },
          },
        ],
        'next': null,
      };
    }
    throw FormatException('测试不支持 $path');
  }
}

void main() {
  test('configured form enforces exclusivity, bounds and valid enums', () {
    final q3 = questions.firstWhere((q) => q['id'] == 'q3');
    expect(toggleTeamAnswer(q3, ['Q3_A', 'Q3_B'], 'Q3_G'), ['Q3_G']);
    expect(toggleTeamAnswer(q3, ['Q3_G'], 'Q3_A'), ['Q3_A']);
    expect(toggleTeamAnswer(q3, ['Q3_A', 'Q3_B', 'Q3_C'], 'Q3_D'), [
      'Q3_A',
      'Q3_B',
      'Q3_C',
    ]);
    for (final invalid in [
      [],
      ['Q3_A', 'Q3_A'],
      ['Q3_G', 'Q3_A'],
      ['invalid'],
    ]) {
      expect(teamAnswerError(q3, invalid), isNotNull);
    }
    final q10 = questions.firstWhere((q) => q['id'] == 'q10');
    expect(teamAnswerError(q10, ['Q10_A', 'Q10_B', 'Q10_C']), isNotNull);
  });

  test(
    'authorized availability respects busy periods and returns anonymous slots',
    () {
      final data = ScheduleData(
        semester: Semester(startDate: SchoolClock.instant(2026, 9, 7)),
        courses: [
          Course(
            name: '不应上传的课程名称',
            meetings: [
              WeeklyMeeting(
                weekday: 1,
                startPeriod: 1,
                endPeriod: 1,
                startWeek: 1,
                endWeek: 16,
              ),
            ],
          ),
        ],
      );
      final monday = SchoolClock.instant(2026, 10, 12);
      final slots = teamFreeSlots(data, monday);
      expect(slots.contains(16), false); // 08:00 lesson
      expect(slots.contains(17), false); // overlapping 08:30–08:45
      expect(slots.contains(18), true); // 09:00 free
      expect(slots.every((s) => s >= 0 && s < 336), true);
      expect(teamSlotLabel(18), '周一 09:00–09:30');
      expect(
        () => teamFreeSlots(data, SchoolClock.instant(2027, 9, 6)),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'first questionnaire has ten questions, allows back, saves profile and round separately',
    (tester) async {
      final fake = FakeTeamDiscussion();
      addTearDown(fake.close);
      await tester.pumpWidget(
        MaterialApp(
          home: TeamQuestionnairePage(
            client: TeamClient(fake),
            config: config,
            roundId: 'first-round',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 5 页'), findsOneWidget);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('请完成本题。'), findsOneWidget);
      for (var page = 0; page < 5; page++) {
        for (final q in questions.skip(page * 2).take(2)) {
          final label = q['options'][0]['label'] as String;
          await tester.scrollUntilVisible(
            find.text(label),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).hitTestable());
          await tester.pumpAndSettle();
        }
        if (page == 1) {
          await tester.tap(find.text('上一步'));
          await tester.pumpAndSettle();
          expect(find.text('第 1 / 5 页'), findsOneWidget);
          await tester.tap(find.text('下一步'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(page == 4 ? '保存偏好' : '下一步'));
        await tester.pumpAndSettle();
      }
      final savedProfile = fake.writes
          .firstWhere((w) => w.$1 == 'v1/team-profile')
          .$2;
      final savedRound = fake.writes
          .firstWhere((w) => w.$1 == 'v1/team-preferences/first-round')
          .$2;
      expect((savedProfile['answers'] as Json).length, 7);
      expect((savedRound['answers'] as Json).keys.toSet(), {'q1', 'q2', 'q7'});
      expect(savedRound['canMeetOffline'], false);
    },
  );

  testWidgets('subsequent round asks only three contextual questions', (
    tester,
  ) async {
    final fake = FakeTeamDiscussion(hasProfile: true);
    addTearDown(fake.close);
    await tester.pumpWidget(
      MaterialApp(
        home: TeamQuestionnairePage(
          client: TeamClient(fake),
          config: config,
          roundId: 'second-round',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(
      find.text(
        questions.firstWhere((q) => q['id'] == 'q3')['title'] as String,
      ),
      findsNothing,
    );
    for (final id in ['q1', 'q2', 'q7']) {
      final q = questions.firstWhere((q) => q['id'] == id);
      await tester.scrollUntilVisible(
        find.text(q['options'][0]['label'] as String),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(q['options'][0]['label'] as String));
      await tester.pump();
      if (id == 'q2') {
        await tester.tap(find.text('下一步'));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.text('保存偏好'));
    await tester.pumpAndSettle();
    expect(fake.writes.any((w) => w.$1 == 'v1/team-profile'), false);
    expect(fake.writes.single.$1, 'v1/team-preferences/second-round');
  });

  testWidgets('课程组队直接浏览招募，两个入口分开显示，空我的队伍可创建', (tester) async {
    final fake = FakeTeamDiscussion();
    addTearDown(fake.close);
    final room = DiscussionRoom({
      'roomKey': 'ROOM',
      'name': '测试教学班',
      'teachers': ['老师'],
      'attendingClassNames': ['班级'],
      'arrangements': [],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: TeamPage(client: fake, room: room),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正在组队'), findsOneWidget);
    expect(find.text('我的队伍'), findsOneWidget);
    expect(find.text('问卷未补全团队'), findsOneWidget);
    expect(find.text('推荐团队'), findsNothing);
    expect(find.text('合作程度筛选'), findsNothing);
    await tester.tap(find.text('我的队伍'));
    await tester.pumpAndSettle();
    expect(find.text('问卷未补全团队'), findsNothing);
    expect(find.text('创建团队'), findsOneWidget);
    expect(find.textContaining('你还没有加入队伍'), findsOneWidget);
    await tester.tap(find.text('创建团队'));
    await tester.pumpAndSettle();
    expect(find.byType(TeamQuestionnairePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'explicit class consent required and low-confidence score never shown',
    (tester) async {
      final fake = FakeTeamDiscussion(hasConsent: false);
      addTearDown(fake.close);
      final room = DiscussionRoom({
        'roomKey': 'ROOM',
        'name': '测试教学班',
        'teachers': ['老师'],
        'attendingClassNames': ['班级'],
        'arrangements': [],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: TeamPage(client: fake, room: room),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始课程组队'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('我确认属于这个教学班'));
      await tester.pump();
      await tester.tap(find.text('我同意主动参与组队和展示组队身份'));
      await tester.pump();
      await tester.tap(find.text('开始课程组队'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('问卷信息不足，请补全后查看匹配'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('99.9'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('匹配度 77%'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('匹配度 77%'), findsOneWidget);
      expect(fake.writes.single.$2['confirmMembership'], true);
      expect(find.text('新建组队活动'), findsNothing);
      expect(find.textContaining('组队活动（'), findsNothing);
    },
  );
}
