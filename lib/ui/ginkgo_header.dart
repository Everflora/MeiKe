import 'package:flutter/material.dart';
import '../data/schedule_store.dart';
import 'course_editor.dart';
import 'courses_page.dart';
import 'school_import_page.dart';
import 'theme.dart';

class GinkgoHeader extends StatelessWidget {
  const GinkgoHeader({super.key, required this.store});
  final ScheduleStore store;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('ginkgo-brand-header'),
    color: context.meike.hero,
    padding: const EdgeInsets.fromLTRB(16, 6, 14, 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PlumMark(size: 21, color: context.meike.onHero),
                  const SizedBox(width: 8),
                  Text(
                    '梅课',
                    style: TextStyle(
                      fontFamily: 'Songti SC',
                      fontSize: 24,
                      color: context.meike.onHero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'MEIKE · SOUTHEAST',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: const Color(0xFFD1DFBF),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '课程管理',
          onPressed: () => showCourses(context, store),
          icon: Icon(Icons.edit_note_outlined, color: context.meike.onHero),
        ),
        IconButton(
          tooltip: '一键导入学校课表',
          onPressed: store.canWrite && !store.busy
              ? () => importSchoolSchedule(context, store)
              : null,
          icon: Icon(Icons.download_outlined, color: context.meike.onHero),
        ),
        IconButton.filled(
          tooltip: '添加课程',
          style: IconButton.styleFrom(
            backgroundColor: gingko,
            foregroundColor: const Color(0xFF24382E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: store.canWrite && !store.busy
              ? () => editCourse(context, store)
              : null,
          icon: const Icon(Icons.add, color: Color(0xFF24382E)),
        ),
      ],
    ),
  );
}
