import 'package:taktooka/services/page_snapshot_cache.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/core/display_format.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/models/transport_line.dart';
import 'package:taktooka/models/trip_history_filter.dart';
import 'package:taktooka/pages/line_detail_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/trip_history_card.dart';

class HistoryPage extends StatefulWidget {
  final Backend backend;
  final bool active;
  const HistoryPage({super.key, required this.backend, this.active = true});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String filter = 'all';
  List<Json> lineRuns = [];
  bool loading = false;
  String? error, user;
  int epoch = 0;
  List<Json>? _cachedRides, _cachedRuns;
  String? _cachedFilter;
  List<Json> _entries = [];
  Timer? timer;
  @override
  void initState() {
    super.initState();
    widget.backend.addListener(changed);
    user = widget.backend.db.auth.currentUser?.id;
    final cached = PageSnapshotCache.read(widget.backend, 'line-history');
    if (cached != null) lineRuns = Backend.rows(cached['rows']);
    if (widget.active) loadLines();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (widget.active &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        loadLines();
    });
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      oldWidget.backend.removeListener(changed);
      widget.backend.addListener(changed);
      changed();
    }
    if (!oldWidget.active && widget.active) loadLines();
  }

  void changed() {
    final uid = widget.backend.db.auth.currentUser?.id;
    if (uid == user) return;
    epoch++;
    user = uid;
    lineRuns = [];
    loading = false;
    error = null;
    if (widget.active) unawaited(loadLines());
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    epoch++;
    timer?.cancel();
    widget.backend.removeListener(changed);
    super.dispose();
  }

  Future<void> loadLines() async {
    if (loading || !widget.backend.loggedIn) return;
    final current = ++epoch;
    loading = true;
    if (lineRuns.isEmpty && mounted) setState(() {});
    try {
      final rows = Backend.rows(
        await widget.backend.db
            .rpc('tkt_line_history')
            .timeout(const Duration(seconds: 15)),
      );
      if (current == epoch)
        PageSnapshotCache.save(widget.backend, 'line-history', {'rows': rows});
      if (mounted &&
          current == epoch &&
          (!sameSnapshot(lineRuns, rows) || error != null))
        setState(() {
          lineRuns = rows;
          error = null;
        });
    } catch (_) {
      if (mounted && current == epoch)
        setState(() => error = 'تعذّر تحديث رحلات الخط؛ اسحب للتحديث');
    } finally {
      if (mounted && current == epoch) {
        final initial = lineRuns.isEmpty;
        loading = false;
        if (initial) setState(() {});
      }
    }
  }

  Future<void> refresh() async {
    await Future.wait([widget.backend.refresh(), loadLines()]);
  }

  Future<void> openLine(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LineDetailPage(b: widget.backend, id: id),
      ),
    );
    if (mounted) await loadLines();
  }

  String departureClock(dynamic value) => displayTime(value);
  Widget lineCard(Json run) {
    final cancelled = run['line_status'] == 'cancelled';
    final state = cancelled
        ? 'ملغية'
        : lineRunStates[run['state']] ?? 'رحلة خط';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PaperCard(
        onTap: () => openLine(run['line_id']),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppText(
                    lineKinds[run['kind']] ?? 'رحلة خط',
                    style: heading(19),
                  ),
                ),
                Chip(
                  label: AppText(state, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
            AppText(
              '${run['service_date']} • الانطلاق ${departureClock(run['departure_at'])}',
              style: const TextStyle(color: muted),
            ),
            const SizedBox(height: 10),
            AppText('الراكب: ${run['passenger_name']}'),
            Row(
              children: [
                const Icon(Icons.location_on, color: scarlet),
                Expanded(child: AppText('من: ${run['pickup_name']}')),
              ],
            ),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue),
                Expanded(child: AppText('إلى: ${run['destination_name']}')),
              ],
            ),
            if (run['late_at'] != null)
              const AppText(
                '⚠ سُجّل تحذير تأخير لهذا المشوار',
                style: TextStyle(color: scarlet),
              ),
            const Divider(height: 24),
            AppText(
              'إجمالي أجور الخط: ${money(run['total_price'])}',
              style: heading(17),
            ),
            AppText(
              '${run['service_days']} يوم خدمة • الدفع بنهاية مدة الخط ${run['end_date']}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            TextButton(
              onPressed: () => openLine(run['line_id']),
              child: const AppText('تفاصيل الخط والتتبع ←'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedFilter != filter ||
        !sameSnapshot(_cachedRides, widget.backend.rides) ||
        !sameSnapshot(_cachedRuns, lineRuns)) {
      _entries = filterTripHistory(widget.backend.rides, lineRuns, filter);
      _cachedRides = widget.backend.rides;
      _cachedRuns = lineRuns;
      _cachedFilter = filter;
    }
    final entries = _entries;
    final header = <Widget>[
      const AppText(
        'رحلاتي',
        style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 14),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          const ButtonSegment(value: 'lines', label: AppText('رحلات الخط')),
          ButtonSegment(
            value: 'customers',
            label: AppText(widget.backend.captain ? 'رحلات زبائن' : 'رحلاتي'),
          ),
          const ButtonSegment(value: 'all', label: AppText('كل الرحلات')),
        ],
        selected: {filter},
        onSelectionChanged: (v) => setState(() => filter = v.first),
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.surface,
          ),
        ),
      ),
      const SizedBox(height: 16),
      if (filter != 'customers' && error != null)
        AppText(error!, style: const TextStyle(color: scarlet)),
      if (filter != 'customers' && loading && lineRuns.isEmpty)
        const LinearProgressIndicator(),
      if (entries.isEmpty && !loading)
        AppText(
          filter == 'lines'
              ? 'ما عندك رحلات خط لحد اليوم.'
              : filter == 'customers'
              ? widget.backend.captain
                    ? 'ما عندك رحلات زبائن بعد.'
                    : 'ما عندك رحلات بعد.'
              : 'ما عندك رحلات بعد.',
        ),
    ];
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        key: const PageStorageKey('trip-history'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: header.length + entries.length,
        itemBuilder: (context, index) {
          if (index < header.length) return header[index];
          final entry = entries[index - header.length];
          return RepaintBoundary(
            child: entry['history_type'] == 'line'
                ? lineCard(entry)
                : TripHistoryCard(ride: entry, captain: widget.backend.captain),
          );
        },
      ),
    );
  }
}
