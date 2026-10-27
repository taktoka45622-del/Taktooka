import 'package:taktooka/services/page_snapshot_cache.dart';
import 'package:taktooka/widgets/line_section.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/core/display_format.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/models/transport_line.dart';
import 'package:taktooka/pages/lines_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/booking_map_layer.dart';

class LineDetailPage extends StatefulWidget {
  final Backend b;
  final String id;
  final Json? initialLine;
  const LineDetailPage({
    super.key,
    required this.b,
    required this.id,
    this.initialLine,
  });
  @override
  State<LineDetailPage> createState() => _LineDetailPageState();
}

class _LineDetailPageState extends State<LineDetailPage> {
  Json? data;
  String? error;
  bool fetching = false,
      busy = false,
      sharing = false,
      attemptedSharing = false,
      routeRequested = false,
      verified = false;
  List<LatLng> routePoints = [];
  final mapController = MapController();
  bool mapReady = false;
  Timer? timer;
  StreamSubscription<dynamic>? gps;
  DateTime lastLocation = DateTime(2000);
  @override
  void initState() {
    super.initState();
    data = PageSnapshotCache.read(widget.b, 'line:${widget.id}');
    if (data == null && widget.initialLine != null) {
      final line = widget.initialLine!;
      data = {
        'line': line,
        'runs': [],
        'customer': {'name': line['customer_name']},
        'captain': null,
      };
    }
    load();
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        load();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    gps?.cancel();
    mapController.dispose();
    super.dispose();
  }

  Object? _timeState(Json? value) {
    if (value == null) return null;
    final now =
        DateTime.tryParse('${value['server_now']}') ?? DateTime.now().toUtc();
    final contact = value['captain'];
    final at = contact is Map
        ? DateTime.tryParse('${contact['location_at']}')
        : null;
    final line = value['line'];
    final due = line is Map
        ? DateTime.tryParse('${line['end_date']}T${line['arrival']}+03:00')
        : null;
    return '${at != null && now.difference(at).inSeconds <= 30}:${due != null && !now.isBefore(due)}';
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    final loadUser = widget.b.db.auth.currentUser?.id;
    try {
      final r = Json.from(await lineRpc(widget.b, 'detail', {'id': widget.id}));
      if (!mounted || loadUser != widget.b.db.auth.currentUser?.id) return;
      PageSnapshotCache.save(widget.b, 'line:${widget.id}', r);
      if (mounted) {
        final previous = data;
        final changed =
            !sameSnapshot(previous, r) ||
            error != null ||
            !verified ||
            _timeState(previous) != _timeState(r);
        if (changed)
          setState(() {
            data = r;
            verified = true;
            error = null;
          });
        else
          data = r;
      }
      if (mounted && !routeRequested) {
        routeRequested = true;
        unawaited(loadRoute(Json.from(r['line'])));
      }
      final line = Json.from(r['line']);
      final uid = widget.b.db.auth.currentUser?.id;
      final now =
          DateTime.tryParse('${r['server_now']}') ?? DateTime.now().toUtc();
      final window = Backend.rows(r['runs']).any((run) {
        final departure = DateTime.parse(run['departure_at']);
        final arrival = DateTime.parse(run['arrival_at']);
        return !['completed', 'missed'].contains(run['state']) &&
            now.isAfter(departure.subtract(const Duration(minutes: 30))) &&
            now.isBefore(arrival.add(const Duration(hours: 1)));
      });
      if (mounted &&
          (line['customer_id'] == uid ||
              (line['captain_id'] == uid && !widget.b.subscribed)) &&
          !busy &&
          line['status'] == 'accepted' &&
          window &&
          !attemptedSharing) {
        attemptedSharing = true;
        unawaited(share());
      }
    } catch (e) {
      if (mounted) setState(() => error = lineError(e));
    } finally {
      fetching = false;
    }
  }

  Future<void> loadRoute(Json l) async {
    final routeUser = widget.b.db.auth.currentUser?.id;
    try {
      final response = await widget.b.db.functions.invoke(
        'taktooka-quote',
        body: {
          'pickup': [l['pickup_lat'], l['pickup_lng']],
          'destination': [l['destination_lat'], l['destination_lng']],
          'round_trip': false,
          'wait_minutes': 0,
        },
      );
      final coordinates = response.data?['geometry']?['coordinates'] as List?;
      if (mounted &&
          routeUser == widget.b.db.auth.currentUser?.id &&
          coordinates != null) {
        setState(
          () => routePoints = coordinates
              .map(
                (p) =>
                    LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()),
              )
              .toList(),
        );
        if (mapReady && routePoints.length > 1) {
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(routePoints),
              padding: const EdgeInsets.all(40),
              maxZoom: 17,
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> action(String action, [Json extra = const {}]) async {
    if (busy || !verified) return;
    setState(() => busy = true);
    try {
      if (action == 'accept') {
        final yes = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const AppText('قبول الخط'),
            content: const AppText(
              'تلتزم بمواعيد هذا الخط وأيامه. تكدر تقبل حتى 3 خطوط ولو بنفس الوقت. موافق؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const AppText('رجوع'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: AppText(
                  widget.b.subscribed
                      ? 'قبول الخط'
                      : 'جدّد اشتراكك لقبول خطوط جديدة',
                ),
              ),
            ],
          ),
        );
        if (yes != true) return;
      }
      if ((action == 'run_state' || action == 'depart' || action == 'accept') &&
          !widget.b.tracking) {
        if (widget.b.subscribed) {
          await widget.b.startTracking();
        } else if (action != 'accept') {
          final fix = await widget.b.locate(fresh: true);
          await lineRpc(widget.b, 'location', {
            'id': widget.id,
            'lat': fix.latitude,
            'lng': fix.longitude,
          });
        }
      }
      final response = await lineRpc(widget.b, action, {
        'id': widget.id,
        ...extra,
      });
      await load();
      if (!mounted || action != 'depart') return;
      final next = response is Map ? response['next_line'] as Map? : null;
      if (next != null) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LineDetailPage(b: widget.b, id: next['line_id']),
          ),
        );
      } else if (extra['mode'] == 'destination' && data != null) {
        final line = Json.from(data!['line']);
        await launchUrl(
          Uri.parse(
            'https://waze.com/ul?navigate=yes&ll=${line['destination_lat']},${line['destination_lng']}',
          ),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: AppText(lineError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share() async {
    if (busy || sharing) return;
    setState(() => busy = true);
    try {
      final pos = await widget.b.locate();
      await lineRpc(widget.b, 'location', {
        'id': widget.id,
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      lastLocation = DateTime.now();
      gps =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
            ),
          ).listen((p) async {
            if (DateTime.now().difference(lastLocation).inSeconds < 3) return;
            lastLocation = DateTime.now();
            try {
              await lineRpc(widget.b, 'location', {
                'id': widget.id,
                'lat': p.latitude,
                'lng': p.longitude,
              });
            } catch (_) {
              if (mounted)
                setState(() => error = 'تعذّر إرسال موقعك؛ تحقق من الاتصال');
            }
          });
      if (mounted) setState(() => sharing = true);
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openPoint(LatLng point) => launchUrl(
    Uri.parse(
      'https://waze.com/ul?navigate=yes&ll=${point.latitude},${point.longitude}',
    ),
    mode: LaunchMode.externalApplication,
  ).then((_) {});

  Widget contactPhone(dynamic value) {
    final phone = '${value ?? ''}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            phone.isEmpty ? '—' : phone,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        if (phone.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
            icon: const Icon(Icons.phone),
            label: const AppText('اتصال'),
          ),
      ],
    );
  }

  Widget fact(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        AppText(
          '${value ?? '—'}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = data == null ? null : Json.from(data!['line']);
    if (l == null)
      return Scaffold(
        appBar: AppBar(title: const AppText('تفاصيل الخط')),
        body: Center(
          child: error == null
              ? const Icon(Icons.route, size: 48, color: muted)
              : AppText(error!),
        ),
      );
    final uid = widget.b.db.auth.currentUser?.id;
    final mine = l['captain_id'] == uid, owner = l['customer_id'] == uid;
    final runs = Backend.rows(data!['runs']);
    final now =
        DateTime.tryParse('${data!['server_now']}') ?? DateTime.now().toUtc();
    final today = now.add(const Duration(hours: 3));
    final dueAt = DateTime.tryParse('${l['end_date']}T${l['arrival']}+03:00');
    final receiptDue =
        ['accepted', 'completed'].contains(l['status']) &&
        l['payment_status'] != 'paid' &&
        dueAt != null &&
        !now.isBefore(dueAt);
    final todays = runs
        .where((r) => r['service_date'] == lineDate(today.toIso8601String()))
        .toList();
    final active = todays.isEmpty ? null : todays.first;
    final nextLine = data!['next_line'] is Map
        ? Json.from(data!['next_line'])
        : null;
    final pickup = LatLng(
      (l['pickup_lat'] as num).toDouble(),
      (l['pickup_lng'] as num).toDouble(),
    );
    final destination = LatLng(
      (l['destination_lat'] as num).toDouble(),
      (l['destination_lng'] as num).toDouble(),
    );
    final contact = Json.from(
      data![(widget.b.captain && !owner) ? 'customer' : 'captain'] as Map? ??
          {},
    );
    final age = DateTime.tryParse('${contact['location_at']}');
    final fresh = age != null && now.difference(age).inSeconds <= 30;
    final points = <Marker>[
      Marker(
        point: pickup,
        child: const Icon(Icons.location_on, color: scarlet, size: 38),
      ),
      Marker(
        point: destination,
        child: const Icon(Icons.location_on, color: Colors.blue, size: 38),
      ),
      if (contact['lat'] != null && contact['lng'] != null)
        Marker(
          point: LatLng(
            (contact['lat'] as num).toDouble(),
            (contact['lng'] as num).toDouble(),
          ),
          child: Icon(
            mine ? Icons.person_pin_circle : Icons.electric_rickshaw,
            color: fresh ? Colors.green : Colors.grey,
            size: 36,
          ),
        ),
    ];
    final showCustomer = widget.b.captain && !owner;
    final customer = Json.from(data!['customer'] as Map? ?? {});
    return Scaffold(
      appBar: AppBar(title: AppText(lineKinds[l['kind']] ?? 'تفاصيل الخط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null)
            AppText(error!, style: const TextStyle(color: scarlet)),
          PaperCard(
            child: Row(
              children: [
                Icon(
                  l['status'] == 'accepted'
                      ? Icons.check_circle
                      : Icons.info_outline,
                  color: l['status'] == 'accepted' ? Colors.green : scarlet,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppText(
                    lineStatuses[l['status']] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LineSection(
            title: 'بيانات الراكب',
            icon: Icons.person,
            children: [fact('الراكب', l['passenger_name'])],
          ),
          LineSection(
            title: 'مسار الخط',
            icon: Icons.route,
            children: [
              fact('نقطة الانطلاق', l['pickup_name']),
              OutlinedButton.icon(
                onPressed: () => openPoint(pickup),
                icon: const Icon(Icons.location_on, color: scarlet),
                label: const AppText('عرض نقطة الانطلاق على الخريطة'),
              ),
              const SizedBox(height: 8),
              fact('نقطة الوصول', l['destination_name']),
              OutlinedButton.icon(
                onPressed: () => openPoint(destination),
                icon: const Icon(Icons.location_on, color: Colors.blue),
                label: const AppText('عرض نقطة الوصول على الخريطة'),
              ),
            ],
          ),
          LineSection(
            title: 'أيام الخدمة',
            icon: Icons.calendar_month,
            children: [
              fact('عدد أيام الخدمة', l['service_days']),
              fact('البداية', l['start_date']),
              fact('النهاية', l['end_date']),
              fact(
                'الأيام المستبعدة',
                (l['excluded_days'] as List)
                    .map((i) => weekDays[i as int])
                    .join('، '),
              ),
            ],
          ),
          if (l['weekly_schedule'] is Map &&
              (l['weekly_schedule'] as Map).isNotEmpty)
            for (final shift in ['morning', 'afternoon'])
              Builder(
                builder: (context) {
                  final schedule = l['weekly_schedule'] as Map;
                  final days =
                      schedule.entries
                          .where((entry) => entry.value['shift'] == shift)
                          .toList()
                        ..sort(
                          (a, b) => int.parse(
                            '${a.key}',
                          ).compareTo(int.parse('${b.key}')),
                        );
                  if (days.isEmpty) return const SizedBox.shrink();
                  final time = days.first.value;
                  return LineSection(
                    title: shift == 'morning'
                        ? 'الدوام الصباحي'
                        : 'الدوام الظهري',
                    icon: Icons.schedule,
                    children: [
                      AppText(
                        days
                            .map((entry) => weekDays[int.parse('${entry.key}')])
                            .join('، '),
                      ),
                      fact('وقت الانطلاق', displayClock(time['departure'])),
                      fact('وقت الوصول', displayClock(time['arrival'])),
                      fact(
                        'وقت الرجوع للمنزل',
                        displayClock(time['return_home']),
                      ),
                    ],
                  );
                },
              )
          else
            LineSection(
              title: 'مواعيد الخط',
              icon: Icons.schedule,
              children: [
                fact('وقت الانطلاق', displayClock(l['departure'])),
                fact('وقت الوصول', displayClock(l['arrival'])),
                fact(
                  'وقت الرجوع للمنزل',
                  l['return_home'] == null
                      ? 'غير محدد'
                      : displayClock(l['return_home']),
                ),
              ],
            ),
          LineSection(
            title: 'الأجور والدفع',
            icon: Icons.payments,
            children: [
              AppText(
                money(l['total_price']),
                style: const TextStyle(
                  color: scarlet,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              fact('الدفع', linePaymentStates[l['payment_status']]),
            ],
          ),
          if (showCustomer)
            LineSection(
              title: 'بيانات الزبون',
              icon: Icons.contact_phone,
              children: [
                fact('الزبون', customer['name']),
                contactPhone(customer['phone']),
              ],
            )
          else if (data!['captain'] is Map)
            LineSection(
              title: 'الكابتن',
              icon: Icons.contact_phone,
              children: [
                fact('الكابتن', data!['captain']['name']),
                contactPhone(data!['captain']['phone']),
              ],
            ),
          const SizedBox(height: 12),
          if (l['status'] == 'pending' && widget.b.captain && !owner)
            FilledButton(
              onPressed: busy || !verified || !widget.b.subscribed
                  ? null
                  : () => action('accept'),
              child: AppText(
                widget.b.subscribed
                    ? 'قبول الخط'
                    : 'جدّد اشتراكك لقبول خطوط جديدة',
              ),
            ),
          if (l['status'] == 'pending' && owner)
            TextButton(
              onPressed: busy ? null : () => action('cancel'),
              child: const AppText('إلغاء طلب الخط'),
            ),
          if (active != null && active['late_at'] != null)
            PaperCard(
              child: AppText(
                '⚠ تحذير تأخر الخط: لم يتم استلام الركاب خلال 5 دقائق من الموعد\nالحالة الحالية: ${lineRunStates[active['state']]}',
                style: const TextStyle(color: scarlet),
              ),
            ),
          if (['pending', 'accepted'].contains(l['status'])) ...[
            AppText(
              l['status'] == 'pending' ? 'خريطة مسار الخط' : 'التتبع المباشر',
              style: heading(19),
            ),
            SizedBox(
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: mapController,
                  options: MapOptions(
                    onMapReady: () => mapReady = true,
                    initialCenter: pickup,
                    initialZoom: 14,
                    maxZoom: 20,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    initialCameraFit: CameraFit.bounds(
                      bounds: LatLngBounds.fromPoints([
                        pickup,
                        destination,
                        ...routePoints,
                      ]),
                      maxZoom: 17,
                      padding: const EdgeInsets.all(40),
                    ),
                  ),
                  children: [
                    const BookingMapLayer(),
                    if (routePoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            color: scarlet,
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(markers: points),
                  ],
                ),
              ),
            ),
            if (l['status'] == 'accepted')
              AppText(
                contact['lat'] == null
                    ? 'بانتظار مشاركة الموقع الحالي'
                    : fresh
                    ? 'الموقع يتحدث مباشرة'
                    : 'الموقع قديم • آخر تحديث ${contact['location_at']}',
              ),
            if (owner && l['status'] == 'accepted')
              OutlinedButton(
                onPressed: busy || sharing ? null : share,
                child: AppText(
                  sharing
                      ? 'موقعك يُشارك أثناء فتح تفاصيل الخط وقرب موعده'
                      : 'مشاركة موقعي مع الكابتن وقت الخط',
                ),
              ),
            if (mine)
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://waze.com/ul?navigate=yes&ll=${active?['state'] == 'picked_up' ? destination.latitude : pickup.latitude},${active?['state'] == 'picked_up' ? destination.longitude : pickup.longitude}',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.navigation),
                label: AppText(
                  active?['state'] == 'picked_up'
                      ? 'التوجّه لنقطة الوصول'
                      : 'التوجّه لنقطة الانطلاق',
                ),
              ),
            if (contact['phone'] != null)
              TextButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse('tel:${contact['phone']}')),
                icon: const Icon(Icons.phone),
                label: const AppText('اتصال'),
              ),
            if (mine &&
                active != null &&
                !['completed', 'missed'].contains(active['state'])) ...[
              if (['scheduled', 'heading'].contains(active['state']))
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => action('run_state', {
                          'run_id': active['id'],
                          'state': active['state'] == 'scheduled'
                              ? 'heading'
                              : 'arrived',
                        }),
                  child: AppText(
                    active['state'] == 'scheduled'
                        ? 'متوجه لاستلام الركاب'
                        : 'لقد وصلت',
                  ),
                ),
              if (['arrived', 'picked_up'].contains(active['state'])) ...[
                if (active['state'] == 'arrived')
                  const AppText(
                    'بعد ركوب الراكب اختَر خطك التالي أو توجّه إلى الوجهة.',
                  ),
                if (nextLine != null)
                  PaperCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText('الخط التالي حان موعده', style: heading(17)),
                        AppText(
                          '${nextLine['passenger_name']} • ${nextLine['pickup_name']}',
                        ),
                        AppText(
                          'يبعد ${(nextLine['distance_m'] as num).round()} متر عن هذا الخط',
                        ),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => action('depart', {
                                  'run_id': active['id'],
                                  'mode': 'next',
                                }),
                          icon: const Icon(Icons.route),
                          label: const AppText('انطلاق للخط التالي'),
                        ),
                      ],
                    ),
                  )
                else
                  const AppText(
                    'ماكو خط قريب حان موعده؛ تكدر تتوجه إلى الوجهة.',
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => action('depart', {
                          'run_id': active['id'],
                          'mode': 'destination',
                        }),
                  icon: const Icon(Icons.navigation),
                  label: const AppText('ذهاب إلى الوجهة'),
                ),
              ],
            ],
          ],
          if (mine && Backend.rows(data!['onboard']).isNotEmpty) ...[
            const SizedBox(height: 14),
            AppText('الركاب وياك — وجهات الوصول', style: heading(19)),
            for (final passenger in Backend.rows(data!['onboard']))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PaperCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppText(passenger['passenger_name'], style: heading(17)),
                      AppText(passenger['destination_name']),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(
                            'https://waze.com/ul?navigate=yes&ll=${passenger['destination_lat']},${passenger['destination_lng']}',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.navigation),
                        label: const AppText('الذهاب لهذه الوجهة'),
                      ),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () => action('run_state', {
                                'id': passenger['line_id'],
                                'run_id': passenger['run_id'],
                                'state': 'completed',
                              }),
                        child: const AppText('وصل الراكب إلى وجهته'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          if (owner && l['payment_status'] == 'due')
            FilledButton(
              onPressed: busy ? null : () => action('payment'),
              child: AppText('أؤكد دفع ${money(l['total_price'])} للكابتن'),
            ),
          if (mine && receiptDue)
            FilledButton(
              onPressed: busy ? null : () => action('payment'),
              child: const AppText('لقد استلمت الأموال'),
            ),
          const SizedBox(height: 16),
          AppText('جدول الخط', style: heading(20)),
          for (final r in runs)
            ListTile(
              title: AppText(
                '${r['service_date']} • ${lineRunStates[r['state']]}',
              ),
              subtitle: AppText(
                'وقت الانطلاق: ${displayTime(r['departure_at'])} • وقت الوصول: ${displayTime(r['arrival_at'])}${r['return_at'] == null ? '' : ' • وقت الرجوع للمنزل: ${displayTime(r['return_at'])}'}${r['late_at'] == null ? '' : '\nسُجّل تحذير تأخير'}',
              ),
              leading: Icon(
                r['state'] == 'completed'
                    ? Icons.check_circle
                    : Icons.calendar_today,
                color: r['late_at'] == null ? muted : scarlet,
              ),
            ),
        ],
      ),
    );
  }
}
