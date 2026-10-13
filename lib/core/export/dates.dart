import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter({String? locale, this.utc = false, DateTime? now})
    : locale = locale ?? 'en_US',
      now = now ?? DateTime.now();

  final String locale;
  final bool utc;
  final DateTime now;

  late final _short = DateFormat.yMd(locale).add_jm();
  late final _full = DateFormat.yMMMMEEEEd(locale).add_jms();
  late final _time = DateFormat.jm(locale);
  late final _longTime = DateFormat.jms(locale);
  late final _date = DateFormat.yMd(locale);
  late final _longDate = DateFormat.yMMMMd(locale);
  late final _dateTime = DateFormat.yMMMMd(locale).add_jm();
  late final _weekdayDateTime = DateFormat.yMMMMEEEEd(locale).add_jm();

  DateTime _zone(DateTime time) => utc ? time.toUtc() : time.toLocal();

  String _suffix(DateTime time) => utc ? ' UTC' : '';

  String short(DateTime time) => _short.format(_zone(time));
  String full(DateTime time) => '${_full.format(_zone(time))}${_suffix(time)}';
  String time(DateTime time) => _time.format(_zone(time));
  String day(DateTime time) => _longDate.format(_zone(time));
  String dayKey(DateTime time) {
    final t = _zone(time);
    return '${t.year}-${t.month}-${t.day}';
  }

  String styled(DateTime time, String? style) => switch (style) {
    't' => _time.format(_zone(time)),
    'T' => _longTime.format(_zone(time)),
    'd' => _date.format(_zone(time)),
    'D' => _longDate.format(_zone(time)),
    'F' => _weekdayDateTime.format(_zone(time)),
    'R' => relative(time),
    _ => _dateTime.format(_zone(time)),
  };

  String relative(DateTime time) {
    final diff = time.difference(now);
    final past = diff.isNegative;
    final seconds = diff.inSeconds.abs();
    String amount;
    if (seconds < 45) {
      amount = 'a few seconds';
    } else if (seconds < 90) {
      amount = 'a minute';
    } else if (seconds < 45 * 60) {
      amount = '${(seconds / 60).round()} minutes';
    } else if (seconds < 90 * 60) {
      amount = 'an hour';
    } else if (seconds < 22 * 3600) {
      amount = '${(seconds / 3600).round()} hours';
    } else if (seconds < 36 * 3600) {
      amount = 'a day';
    } else if (seconds < 26 * 86400) {
      amount = '${(seconds / 86400).round()} days';
    } else if (seconds < 46 * 86400) {
      amount = 'a month';
    } else if (seconds < 320 * 86400) {
      amount = '${(seconds / (30 * 86400)).round()} months';
    } else if (seconds < 548 * 86400) {
      amount = 'a year';
    } else {
      amount = '${(seconds / (365 * 86400)).round()} years';
    }
    return past ? '$amount ago' : 'in $amount';
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value < 10 ? 2 : 1)} ${units[unit]}';
}

String formatDuration(Duration duration) {
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60);
  final s = duration.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
