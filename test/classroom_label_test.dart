import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/ui/classroom_label.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    String location = '教三-304',
    double width = 80,
    int maxLines = 2,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Center(
            child: SizedBox(
              width: width,
              child: ClassroomLabel(
                location,
                maxLines: maxLines,
                style: const TextStyle(fontSize: 9, height: 1.1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('有空间时教室保持完整一行', (tester) async {
    await show(tester);
    expect(find.text('教三-304'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄格子仅在楼栋与房号之间换行且完整可见', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, width: 30);
    expect(find.text('教'), findsNothing);
    expect(find.text('教三-'), findsOneWidget);
    expect(find.text('304'), findsOneWidget);
    expect(
      tester.getRect(find.text('教三-')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('304')).top),
    );
    final box = tester.getRect(find.byType(ClassroomLabel));
    for (final element in find.byType(FittedBox).evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.width, lessThanOrEqualTo(box.width));
      expect(rect.bottom, lessThanOrEqualTo(box.bottom));
    }
    expect(find.bySemanticsLabel('教三-304'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('单节课空间不足时整行缩放，不省略房号', (tester) async {
    await show(tester, width: 25, maxLines: 1);
    expect(find.text('教三-304'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(tester.getSize(find.byType(FittedBox)).width, lessThanOrEqualTo(25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('无分隔符的体育馆名称不被任意拆字', (tester) async {
    await show(tester, location: '体育馆2楼', width: 25);
    expect(find.text('体育馆2楼'), findsOneWidget);
    expect(find.byType(Text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分隔圆点与大字体仍保留楼栋和完整房号', (tester) async {
    await show(tester, location: '教三 · 304', width: 30, textScale: 2);
    expect(find.text('教三 ·'), findsOneWidget);
    expect(find.text('304'), findsOneWidget);
    expect(find.text('教'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
