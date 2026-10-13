import 'package:sqlite3/sqlite3.dart';

enum MediaStatus { pending, uploaded, failed }

class JobMedia {
  const JobMedia({
    required this.job,
    required this.part,
    required this.key,
    required this.source,
    required this.path,
    required this.name,
    required this.size,
    required this.sha256,
    required this.contentType,
    required this.fallback,
    required this.temporary,
    this.status = MediaStatus.pending,
    this.url,
  });

  final String job;
  final int part;
  final String key;
  final String source;
  final String path;
  final String name;
  final int size;
  final String sha256;
  final String contentType;
  final String fallback;
  final bool temporary;
  final MediaStatus status;
  final String? url;

  String get resolved =>
      status == MediaStatus.uploaded && url != null ? url! : fallback;
}

class UploadCache {
  UploadCache._(this._db) {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('''
CREATE TABLE IF NOT EXISTS hosted (
  provider TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  url TEXT NOT NULL,
  size INTEGER NOT NULL,
  created INTEGER NOT NULL,
  PRIMARY KEY (provider, sha256)
)''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS sources (
  source TEXT NOT NULL,
  provider TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  PRIMARY KEY (source, provider)
)''');
    _db.execute('''
CREATE TABLE IF NOT EXISTS job_media (
  job TEXT NOT NULL,
  part INTEGER NOT NULL,
  key TEXT NOT NULL,
  source TEXT NOT NULL,
  path TEXT NOT NULL,
  name TEXT NOT NULL,
  size INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  content_type TEXT NOT NULL,
  fallback TEXT NOT NULL,
  temporary INTEGER NOT NULL,
  status INTEGER NOT NULL DEFAULT 0,
  url TEXT,
  PRIMARY KEY (job, part, key)
)''');
  }

  factory UploadCache.open(String path) => UploadCache._(sqlite3.open(path));

  factory UploadCache.memory() => UploadCache._(sqlite3.openInMemory());

  final Database _db;

  String? bySource(String source, List<String> providers) {
    for (final provider in providers) {
      final rows = _db.select(
        'SELECT h.url FROM sources s JOIN hosted h '
        'ON h.provider = s.provider AND h.sha256 = s.sha256 '
        'WHERE s.source = ? AND s.provider = ?',
        [source, provider],
      );
      if (rows.isNotEmpty) return rows.first['url'] as String;
    }
    return null;
  }

  ({String provider, String url})? byHash(
    String sha256,
    List<String> providers,
  ) {
    for (final provider in providers) {
      final rows = _db.select(
        'SELECT url FROM hosted WHERE provider = ? AND sha256 = ?',
        [provider, sha256],
      );
      if (rows.isNotEmpty) {
        return (provider: provider, url: rows.first['url'] as String);
      }
    }
    return null;
  }

  void remember({
    required String provider,
    required String sha256,
    required String url,
    required int size,
    String? source,
  }) {
    _db.execute('INSERT OR REPLACE INTO hosted VALUES (?, ?, ?, ?, ?)', [
      provider,
      sha256,
      url,
      size,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    if (source != null) linkSource(source, provider, sha256);
  }

  void linkSource(String source, String provider, String sha256) => _db.execute(
    'INSERT OR REPLACE INTO sources VALUES (?, ?, ?)',
    [source, provider, sha256],
  );

  int get hostedCount =>
      _db.select('SELECT COUNT(*) AS n FROM hosted').first['n'] as int;

  void forgetProvider(String provider) {
    _db.execute('DELETE FROM hosted WHERE provider = ?', [provider]);
    _db.execute('DELETE FROM sources WHERE provider = ?', [provider]);
  }

  void clearHosted() {
    _db.execute('DELETE FROM hosted');
    _db.execute('DELETE FROM sources');
  }

  void putJobMedia(JobMedia m) => _db.execute(
    'INSERT OR REPLACE INTO job_media '
    '(job, part, key, source, path, name, size, sha256, content_type, '
    'fallback, temporary, status, url) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      m.job,
      m.part,
      m.key,
      m.source,
      m.path,
      m.name,
      m.size,
      m.sha256,
      m.contentType,
      m.fallback,
      m.temporary ? 1 : 0,
      m.status.index,
      m.url,
    ],
  );

  List<JobMedia> jobMedia(String job, {int? part}) => _db
      .select(
        part == null
            ? 'SELECT * FROM job_media WHERE job = ?'
            : 'SELECT * FROM job_media WHERE job = ? AND part = ?',
        [job, ?part],
      )
      .map(
        (row) => JobMedia(
          job: row['job'] as String,
          part: row['part'] as int,
          key: row['key'] as String,
          source: row['source'] as String,
          path: row['path'] as String,
          name: row['name'] as String,
          size: row['size'] as int,
          sha256: row['sha256'] as String,
          contentType: row['content_type'] as String,
          fallback: row['fallback'] as String,
          temporary: row['temporary'] == 1,
          status: MediaStatus.values[row['status'] as int],
          url: row['url'] as String?,
        ),
      )
      .toList();

  void resolveJobMedia(
    String job,
    int part,
    String key, {
    required MediaStatus status,
    String? url,
  }) => _db.execute(
    'UPDATE job_media SET status = ?, url = ? '
    'WHERE job = ? AND part = ? AND key = ?',
    [status.index, url, job, part, key],
  );

  void deleteJobMedia(String job, {int? part}) => _db.execute(
    part == null
        ? 'DELETE FROM job_media WHERE job = ?'
        : 'DELETE FROM job_media WHERE job = ? AND part = ?',
    [job, ?part],
  );

  void close() => _db.close();
}
