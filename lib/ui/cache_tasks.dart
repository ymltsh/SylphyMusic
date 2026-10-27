import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_controller.dart';

class CacheTasksPage extends StatefulWidget {
  const CacheTasksPage({super.key, required this.app});
  final SylphyApp app;
  @override
  State<CacheTasksPage> createState() => _CacheTasksPageState();
}

class _CacheTasksPageState extends State<CacheTasksPage> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) reload();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  late Future<List<Map<String, Object?>>> records = _load();
  Future<List<Map<String, Object?>>> _load() async {
    return widget.app.db.db.rawQuery('''
      SELECT j.id, j.label, j.state,COUNT(i.position) total,
      SUM(CASE WHEN i.state='done' THEN 1 ELSE 0 END) done,
      SUM(CASE WHEN i.state='failed' THEN 1 ELSE 0 END) failed
      FROM cache_jobs j LEFT JOIN cache_job_items i ON i.job_id=j.id
      GROUP BY j.id ORDER BY j.created DESC LIMIT 100
    ''');
  }

  void reload() => setState(() {
    records = _load();
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('缓存任务'),
      actions: [
        IconButton(
          tooltip: widget.app.jobs.paused ? '继续缓存' : '暂停缓存',
          onPressed: () async {
            if (widget.app.jobs.paused) {
              await widget.app.jobs.resume();
            } else {
              await widget.app.jobs.pause();
            }
            reload();
          },
          icon: Icon(widget.app.jobs.paused ? Icons.play_arrow : Icons.pause),
        ),
        IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: records,
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) return const Center(child: Text('尚未创建缓存任务'));
        return ListView(
          children: rows.map((r) {
            final total = (r['total'] as int? ?? 0),
                done = (r['done'] as int? ?? 0),
                failed = (r['failed'] as int? ?? 0);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                title: Text(r['label']?.toString() ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r['state']} · 完成 $done / $total · 失败 $failed'),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                    ),
                  ],
                ),
                trailing: r['state'] == 'failed'
                    ? IconButton(
                        tooltip: '重试失败项',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          await widget.app.jobs.retry(r['id'] as String);
                          reload();
                        },
                      )
                    : IconButton(
                        tooltip: '取消任务',
                        icon: const Icon(Icons.close),
                        onPressed: () => _cancel(r['id'] as String),
                      ),
              ),
            );
          }).toList(),
        );
      },
    ),
  );
  Future<void> _cancel(String id) async {
    await widget.app.jobs.cancelJob(id);
    reload();
  }
}
