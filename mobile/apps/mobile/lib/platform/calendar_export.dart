class BusyBlock {
  const BusyBlock({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
}

class CalendarTask {
  const CalendarTask({required this.id, required this.title, required this.start,
    required this.end, required this.revision});
  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final int revision;
}

/// RFC 5545. Exports only app tasks, never calendar titles or private busy events.
String exportCalendar(List<CalendarTask> tasks, {required DateTime generatedAt}) {
  String date(DateTime v) => v.toUtc().toIso8601String().replaceAll('-', '')
    .replaceAll(':', '').replaceAll(RegExp(r'\.\d+Z$'), 'Z');
  String escape(String v) => v.replaceAll('\\', '\\\\').replaceAll('\n', '\\n')
    .replaceAll(',', '\\,').replaceAll(';', '\\;').replaceAll('\r', '');
  final lines = <String>['BEGIN:VCALENDAR', 'VERSION:2.0',
    'PRODID:-//Crispy Crust//Bake plan//EN', 'CALSCALE:GREGORIAN'];
  for (final task in tasks) {
    if (!task.end.isAfter(task.start)) throw ArgumentError('Calendar task must have positive duration');
    lines.addAll(['BEGIN:VEVENT', 'UID:${escape(task.id)}@crispycrust.app',
      'DTSTAMP:${date(generatedAt)}', 'DTSTART:${date(task.start)}',
      'DTEND:${date(task.end)}', 'SEQUENCE:${task.revision}',
      'SUMMARY:${escape(task.title)}', 'END:VEVENT']);
  }
  lines.add('END:VCALENDAR');
  return '${lines.join('\r\n')}\r\n';
}
