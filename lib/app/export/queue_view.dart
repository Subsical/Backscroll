import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/export/dates.dart';
import '../../core/export/job.dart';
import '../../core/export/options.dart';
import '../scope.dart';
import '../services/file_manager.dart';
import '../state/exports.dart';
import '../theme.dart';
import '../viewer/export_viewer.dart';
import '../widgets/common.dart';
import 'convert.dart';

class QueueView extends StatelessWidget {
  const QueueView({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final exports = AppScope.of(context).exports;
    return ListenableBuilder(
      listenable: exports,
      builder: (context, _) {
        final jobs = exports.jobs;
        final stats = exports.uploadStats;
        final interrupted = exports.queue.interrupted;
        final finished = jobs.any((j) => j.isFinished);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Exports — ${jobs.length}',
                      style: Styles.sectionLabel,
                    ),
                    const Spacer(),
                    if (!isMobileOS)
                      _Action(
                        Icons.swap_horiz_rounded,
                        'Convert a file',
                        () => convertFile(context),
                      ),
                    if (finished)
                      TextButton(
                        onPressed: exports.queue.clearFinished,
                        child: const Text(
                          'Clear finished',
                          style: TextStyle(color: Palette.muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: jobs.isEmpty && stats.total == 0
                  ? const _Empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      children: [
                        if (interrupted.length > 1)
                          _Banner(
                            key: const ValueKey('resume-all'),
                            text:
                                '${interrupted.length} exports stopped before they finished.',
                            action: 'Resume all',
                            onTap: exports.queue.resumeAll,
                          ),
                        if (stats.total > 0)
                          const UploadCard(key: ValueKey('uploads')),
                        for (final job in jobs.reversed)
                          JobTile(key: ValueKey(job.id), job: job),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.inventory_2_outlined, size: 40, color: Palette.faint),
        SizedBox(height: 12),
        Text(
          'Nothing exported yet',
          style: TextStyle(color: Palette.header, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4),
        Text(
          'Pick a channel and hit Export. Progress shows up here.',
          textAlign: TextAlign.center,
          style: Styles.small,
        ),
      ],
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.text,
    required this.action,
    required this.onTap,
  });

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: Palette.blurple,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Palette.blurple,
          ),
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class UploadCard extends StatelessWidget {
  const UploadCard({super.key});

  @override
  Widget build(BuildContext context) {
    final exports = AppScope.of(context).exports;
    return ListenableBuilder(
      listenable: exports,
      builder: (context, _) => _build(exports),
    );
  }

  Widget _build(ExportsController exports) {
    final stats = exports.uploadStats;
    final finished = stats.done + stats.failed;
    final busy = !stats.idle;
    final providers = exports.settings.providers;
    final active = [
      for (final e in stats.activeByProvider.entries)
        if (e.value > 0)
          '${providers.where((p) => p.id == e.key).firstOrNull?.name ?? 'Host'} ${e.value}',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: Styles.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                busy ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                size: 20,
                color: busy ? Palette.text : Palette.green,
              ),
              const SizedBox(width: 8),
              Text(
                busy ? 'Uploading attachments' : 'Uploads finished',
                style: const TextStyle(
                  color: Palette.header,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (!busy)
                Clickable(
                  onTap: exports.uploads.resetStats,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Palette.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ThinProgress(
            value: stats.totalBytes == 0
                ? null
                : stats.sentBytes / stats.totalBytes,
            color: Palette.green,
          ),
          const SizedBox(height: 8),
          Text(
            [
              '$finished of ${stats.total} files',
              '${formatBytes(stats.sentBytes)} of ${formatBytes(stats.totalBytes)}',
              if (busy && stats.bytesPerSecond > 0)
                '${formatBytes(stats.bytesPerSecond.round())}/s',
              if (busy && (stats.eta?.inSeconds ?? 0) > 0)
                '${formatDuration(stats.eta!)} left',
            ].join(' · '),
            style: Styles.small,
          ),
          if (active.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Active: ${active.join(', ')}', style: Styles.tiny),
            ),
          if (stats.failed > 0 && stats.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${stats.failed} kept their original link. Last error: ${stats.lastError}',
                style: const TextStyle(color: Palette.yellow, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class JobTile extends StatelessWidget {
  const JobTile({super.key, required this.job});

  final ExportJob job;

  Future<void> _open(BuildContext context) async {
    final part = job.parts.where((p) => p.finalized).firstOrNull;
    if (part == null) return;
    final path = job.partPath(part);
    if (isMobileOS) {
      if (job.options.format.isHtml) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ExportViewer(path: path, title: job.title),
          ),
        );
      } else {
        await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      }
      return;
    }
    await launchUrl(Uri.file(path));
  }

  Future<void> _reveal(BuildContext context) async {
    final part = job.parts.where((p) => p.finalized).firstOrNull;
    final folder = job.options.outputDir;
    final shown = await showInFileManager(
      folder,
      file: part == null ? null : job.partPath(part),
    );
    if (!shown && context.mounted) showToast(context, 'Saved in $folder');
  }

  @override
  Widget build(BuildContext context) {
    final exports = AppScope.of(context).exports;
    final queue = exports.queue;
    final (icon, color) = switch (job.status) {
      JobStatus.done => (Icons.check_circle_rounded, Palette.green),
      JobStatus.failed => (Icons.error_rounded, Palette.red),
      JobStatus.cancelled => (Icons.cancel_rounded, Palette.faint),
      JobStatus.paused => (Icons.pause_circle_filled_rounded, Palette.yellow),
      JobStatus.uploading => (Icons.cloud_upload_rounded, Palette.blurple),
      _ => (Icons.downloading_rounded, Palette.blurple),
    };
    final mobile = isMobileOS;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(11, 10, 5, 10),
      decoration: Styles.card.copyWith(
        color: job.isActive ? Palette.selected : Palette.panel,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  style: const TextStyle(
                    color: Palette.header,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    job.guild?.name ?? 'Direct messages',
                    job.options.format.label,
                    if (job.options.pinnedOnly) 'Pins',
                  ].join(' · '),
                  style: Styles.tiny,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (job.status == JobStatus.running ||
                    job.status == JobStatus.uploading) ...[
                  const SizedBox(height: 8),
                  ThinProgress(
                    value: job.status == JobStatus.uploading
                        ? null
                        : job.progress,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  exports.describe(job),
                  style: TextStyle(
                    color: job.status == JobStatus.failed
                        ? Palette.red
                        : Palette.muted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (job.status == JobStatus.running && job.stopping == null)
            _Action(Icons.pause_rounded, 'Pause', () => queue.pause(job)),
          if (job.canResume)
            _Action(
              Icons.play_arrow_rounded,
              job.status == JobStatus.failed ? 'Retry' : 'Resume',
              () => queue.resume(job),
            ),
          if ((job.status == JobStatus.queued ||
                  job.status == JobStatus.running ||
                  job.canResume) &&
              job.stopping != JobStop.cancel)
            _Action(Icons.close_rounded, 'Cancel', () => queue.cancel(job)),
          if (job.status == JobStatus.done && job.parts.isNotEmpty) ...[
            _Action(
              mobile ? Icons.visibility_outlined : Icons.open_in_new_rounded,
              'Open',
              () => _open(context),
            ),
            _Action(
              Icons.folder_open_outlined,
              'Show in folder',
              () => _reveal(context),
            ),
          ],
          if (canConvert(job))
            _More(job: job)
          else if (job.isFinished)
            _Action(
              Icons.delete_outline_rounded,
              'Remove from list',
              () => queue.remove(job),
            ),
        ],
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.job});

  final ExportJob job;

  @override
  Widget build(BuildContext context) {
    final queue = AppScope.of(context).exports.queue;
    return PopupMenuButton<ExportFormat>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      popUpAnimationStyle: AnimationStyle.noAnimation,
      icon: Icon(
        Icons.more_vert_rounded,
        size: isMobileOS ? 24 : 20,
        color: Palette.muted,
      ),
      style: IconButton.styleFrom(
        visualDensity: isMobileOS
            ? VisualDensity.standard
            : VisualDensity.compact,
      ),
      onSelected: (format) => convertJob(context, job, format),
      itemBuilder: (_) => [
        const PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text('Convert to', style: Styles.tiny),
        ),
        for (final format in convertTargets(job.options.format))
          PopupMenuItem(value: format, child: Text(format.label)),
        const PopupMenuDivider(color: Palette.divider),
        PopupMenuItem(
          onTap: () => queue.remove(job),
          child: const Text('Remove from list'),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.tooltip, this.onPressed);

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    icon: Icon(icon, size: isMobileOS ? 24 : 20, color: Palette.muted),
    visualDensity: isMobileOS ? VisualDensity.standard : VisualDensity.compact,
  );
}
