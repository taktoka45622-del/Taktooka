import 'package:taktooka/services/refresh_gate.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/recovery_chat_page.dart';
import 'package:taktooka/services/backend.dart';

class RecoveryInbox extends StatefulWidget {
  final Backend backend;
  const RecoveryInbox({super.key, required this.backend});
  @override
  State<RecoveryInbox> createState() => _RecoveryInboxState();
}

class _RecoveryInboxState extends State<RecoveryInbox> {
  List<Map<String, dynamic>> rows = [];
  String? error;
  Timer? timer;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) { if (mounted && ModalRoute.of(context)?.isCurrent == true && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) unawaited(load()); });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final result = await widget.backend.db
          .from('tkt_recovery_threads')
          .select('id,phone,name,created_at')
          .order('created_at', ascending: false)
          .limit(100);
      final next = result.map((v) => Map<String, dynamic>.from(v)).toList();
      if (mounted && (!sameSnapshot(rows, next) || error != null))
        setState(() {
          rows = next;
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحميل طلبات الدعم');
    } finally {
      loading = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('استرجاع الحسابات')),
    body: RefreshIndicator(
      onRefresh: load,
      child: ListView(
        children: [
          if (error != null)
            TextButton(onPressed: load, child: AppText(error!)),
          if (rows.isEmpty) const ListTile(title: AppText('ماكو طلبات حالياً')),
          for (final row in rows)
            ListTile(
              title: AppText('${row['name']}'),
              subtitle: AppText('${row['phone']}'),
              trailing: const Icon(Icons.chat_outlined),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecoveryChat(
                    backend: widget.backend,
                    adminThread: row['id'] as String,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
