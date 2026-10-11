import 'package:flutter/material.dart';

/// Keep building names intact. Narrow timetable cells may break only at an
/// existing separator; each resulting line scales as a whole if necessary.
class ClassroomLabel extends StatelessWidget {
  const ClassroomLabel(
    this.location, {
    super.key,
    this.style,
    this.maxLines = 2,
  });

  final String location;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      label: location,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: location, style: effectiveStyle),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final fits = painter.width <= constraints.maxWidth;
          painter.dispose();
          final separator = RegExp(r'[-·—–/\s]+').firstMatch(location);
          final canSplit =
              maxLines > 1 &&
              !fits &&
              separator != null &&
              separator.start > 0 &&
              separator.end < location.length;
          final lines = canSplit
              ? [
                  location.substring(0, separator.end).trimRight(),
                  location.substring(separator.end).trimLeft(),
                ]
              : [location];
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      line,
                      style: effectiveStyle,
                      textScaler: scaler,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
