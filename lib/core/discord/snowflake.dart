const discordEpochMs = 1420070400000;

DateTime snowflakeTime(String id) => DateTime.fromMillisecondsSinceEpoch(
  (int.parse(id) >> 22) + discordEpochMs,
  isUtc: true,
);

String snowflakeAt(DateTime time) {
  final ms = time.toUtc().millisecondsSinceEpoch - discordEpochMs;
  return ms <= 0 ? '0' : (ms << 22).toString();
}

int compareSnowflakes(String a, String b) =>
    int.parse(a).compareTo(int.parse(b));

bool isSnowflake(String value) => RegExp(r'^\d{1,20}$').hasMatch(value);
