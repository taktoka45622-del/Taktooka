import 'package:taktooka/widgets/app_notice.dart';
import 'package:taktooka/services/page_snapshot_cache.dart';
import 'package:taktooka/widgets/line_section.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/numeric_localizations.dart';
import 'package:taktooka/core/display_format.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/models/transport_line.dart';
import 'package:taktooka/pages/favorite_place_picker_page.dart';
import 'package:taktooka/pages/line_detail_page.dart';
import 'package:taktooka/services/backend.dart';

Future<dynamic> lineRpc(Backend b, String action, [Json data = const {}]) => b
    .db
    .rpc('tkt_lines', params: {'p_action': action, 'p_data': data})
    .timeout(const Duration(seconds: 20));
String lineDate(dynamic d) => '$d'.split('T').first;

class LinesPage extends StatefulWidget {
  final Backend b;
  final String? initialId;
  const LinesPage({super.key, required this.b, this.initialId});
  @override
  State<LinesPage> createState() => _LinesPageState();
}

class _LinesPageState extends State<LinesPage> {
  List<Json> rows = [];
  bool loading = true, fetching = false;
  String? error;
  Timer? timer;
  bool? lastSubscribed;
  @override
  void initState() {
    super.initState();
    lastSubscribed = widget.b.subscribed;
    widget.b.addListener(subscriptionChanged);
    final cached = PageSnapshotCache.read(widget.b, 'lines');
    if (cached != null) {
      rows = Backend.rows(cached['rows']);
      loading = false;
    }
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        load();
    });
    if (widget.initialId != null)
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => detail(widget.initialId!),
      );
  }

  @override
  void dispose() {
    widget.b.removeListener(subscriptionChanged);
    timer?.cancel();
    super.dispose();
  }

  void subscriptionChanged() {
    if (!mounted || lastSubscribed == widget.b.subscribed) return;
    lastSubscribed = widget.b.subscribed;
    setState(() {});
    load();
  }

  bool locked(Json row) =>
      widget.b.captain &&
      row['captain_id'] != widget.b.db.auth.currentUser?.id &&
      row['customer_id'] != widget.b.db.auth.currentUser?.id &&
      (!widget.b.subscribed || row['locked'] == true);

  void showSubscriptionLock() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('الخط مقفل'),
        content: const AppText('اشترك حتى تشوف تفاصيل الخط وتكدر تقبله.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> load() async {
    if (fetching || !widget.b.loggedIn) {
      if (mounted && loading) setState(() => loading = false);
      return;
    }
    fetching = true;
    final loadUser = widget.b.db.auth.currentUser?.id;
    try {
      final result = Backend.rows(await lineRpc(widget.b, 'list'));
      if (!mounted || loadUser != widget.b.db.auth.currentUser?.id) return;
      PageSnapshotCache.save(widget.b, 'lines', {'rows': result});
      if (mounted && (!sameSnapshot(rows, result) || error != null))
        setState(() {
          rows = result;
          error = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = lineError(e));
    } finally {
      fetching = false;
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> detail(String id) async {
    final row = rows.where((row) => row['id'] == id).firstOrNull;
    if (row != null ? locked(row) : widget.b.captain && !widget.b.subscribed) {
      showSubscriptionLock();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LineDetailPage(
          b: widget.b,
          id: id,
          initialLine: rows.where((row) => row['id'] == id).firstOrNull,
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> register() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RegisterLinePage(b: widget.b)));
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.b.captain &&
        (widget.b.commissionPlan || widget.b.commerce['vehicle'] == 'bike'))
      return Scaffold(
        appBar: AppBar(title: const AppText('الخطوط')),
        body: const Center(
          child: AppText('الخطوط متاحة لكباتن التكتك بنظام الاشتراك الأسبوعي'),
        ),
      );
    final uid = widget.b.db.auth.currentUser?.id;
    final accepted = rows
        .where((r) => r['captain_id'] == uid && r['status'] == 'accepted')
        .length;
    final own = rows
        .where((r) => r['captain_id'] == uid || r['customer_id'] == uid)
        .toList();
    final suggestions = rows
        .where(
          (r) =>
              r['status'] == 'pending' &&
              r['customer_id'] != uid &&
              r['captain_id'] != uid &&
              (r['locked'] == true ||
                  accepted == 0 ||
                  (r['suggestion_distance_m'] is num &&
                      (r['suggestion_distance_m'] as num) <= 1000)),
        )
        .toList();
    suggestions.sort(
      (a, b) => ((a['suggestion_distance_m'] as num?) ?? 0).compareTo(
        (b['suggestion_distance_m'] as num?) ?? 0,
      ),
    );
    final display = widget.b.captain
        ? [
            ...own,
            if (accepted < 3)
              ...suggestions.take(accepted == 0 ? 50 : 3 - accepted),
          ]
        : rows;
    final header = <Widget>[
      if (!widget.b.captain)
        PaperCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                'عندك طلاب وتريد تسويلهم خط للمدرسة؟',
                style: heading(21),
              ),
              const SizedBox(height: 8),
              const AppText(
                'عندك التزام يومي وتريد خط؟ سجّل مسارك وحدد الأيام والوقت والسعر اللي يناسبك.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.b.loggedIn ? register : null,
                child: const AppText('تسجيل خط'),
              ),
              if (!widget.b.loggedIn)
                const AppText('سجّل الدخول من حسابي حتى تسجّل خط'),
            ],
          ),
        )
      else
        PaperCard(
          child: AppText(
            'خطوطك $accepted من 3\n${accepted >= 3
                ? 'التزامك مكتمل؛ تختفي المقترحات لحد ما ينتهي أحد خطوطك.'
                : accepted == 0
                ? 'اختَر خطك الأول، وبعدها نقترح خطوط قريبة منه.'
                : 'نقترح حتى ${3 - accepted} خطوط ضمن 1 كم من أحد خطوطك.'}',
          ),
        ),
      const SizedBox(height: 16),

      if (error != null) AppText(error!),
      if (!loading && rows.isEmpty) const AppText('ماكو خطوط حاليًا'),
    ];
    return Scaffold(
      appBar: AppBar(title: const AppText('الخطوط')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView.builder(
          key: const PageStorageKey('transport-lines'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          itemCount: header.length + display.length,
          itemBuilder: (context, index) {
            if (index < header.length) return header[index];
            final r = display[index - header.length];
            final isLocked = locked(r);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PaperCard(
                onTap: isLocked ? showSubscriptionLock : () => detail(r['id']),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isLocked) ...[
                      const Icon(Icons.lock, color: scarlet, size: 32),
                      AppText(
                        lineKinds[r['kind']] ?? 'خط يومي',
                        style: heading(20),
                      ),
                      const AppText('اشترك حتى تشوف تفاصيل الخط وتكدر تقبله.'),
                    ] else ...[
                      AppText(
                        lineKinds[r['kind']] ?? 'خط يومي',
                        style: heading(20),
                      ),
                      if (widget.b.captain)
                        AppText(
                          r['captain_id'] == uid ? 'من خطوطك' : 'خط مقترح قريب',
                          style: const TextStyle(
                            color: scarlet,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (r['suggestion_distance_m'] != null)
                        AppText(
                          'يبعد عن أقرب خط إلك ${(r['suggestion_distance_m'] as num).round()} متر',
                        ),
                      if (widget.b.captain)
                        AppText('الزبون: ${r['customer_name'] ?? ''}'),
                      AppText('الراكب: ${r['passenger_name']}'),
                      AppText('${r['pickup_name']} ← ${r['destination_name']}'),
                      AppText(
                        '${r['service_days']} يوم خدمة • ${lineDate(r['start_date'])} — ${lineDate(r['end_date'])}',
                      ),
                      AppText(
                        'الانطلاق ${displayClock(r['departure'])} • الوصول ${displayClock(r['arrival'])}',
                      ),
                      if (r['return_home'] != null)
                        AppText(
                          'وقت الرجوع للمنزل: ${displayClock(r['return_home'])}',
                        ),
                      AppText(
                        '${money(r['total_price'])} لكل مدة الخط',
                        style: heading(18),
                      ),
                      AppText(
                        lineStatuses[r['status']] ?? '',
                        style: const TextStyle(color: scarlet),
                      ),
                      if ((r['unresolved_late'] as num? ?? 0) > 0)
                        const AppText(
                          '⚠ تحذير: تأخر استلام الركاب',
                          style: TextStyle(color: scarlet),
                        ),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Icon(Icons.chevron_left),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class RegisterLinePage extends StatefulWidget {
  final Backend b;
  const RegisterLinePage({super.key, required this.b});
  @override
  State<RegisterLinePage> createState() => _RegisterLinePageState();
}

class _RegisterLinePageState extends State<RegisterLinePage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      days = TextEditingController(text: '15'),
      price = TextEditingController();
  final excluded = <int>{5, 6};
  final morningDays = <int>{0, 1, 2};
  final afternoonDays = <int>{3, 4};
  TimeOfDay? afternoonDeparture, afternoonArrival, afternoonReturn;
  DateTime start = DateTime.now().toUtc().add(
    const Duration(hours: 3, days: 1),
  );
  TimeOfDay? departure, arrival, returnHome;
  String kind = 'school';
  AddressChoice? pickup, destination;
  XFile? front, back;
  bool busy = false;
  final draft = const Uuid().v4();
  @override
  void dispose() {
    name.dispose();
    days.dispose();
    price.dispose();
    super.dispose();
  }

  String clock(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Future<void> pick(bool origin) async {
    final value = await Navigator.of(context).push<AddressChoice>(
      MaterialPageRoute(
        builder: (_) => FavoritePlacePicker(
          b: widget.b,
          title: origin ? 'حدد نقطة الانطلاق' : 'حدد نقطة الوصول',
          origin: origin,
        ),
      ),
    );
    if (mounted && value != null)
      setState(() {
        if (origin)
          pickup = value;
        else
          destination = value;
      });
  }

  Future<void> photo(bool face) async {
    try {
      final f = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (mounted && f != null)
        setState(() {
          if (face)
            front = f;
          else
            back = f;
        });
    } catch (_) {
      if (mounted) showAppNotice(context, 'اسمح للتطبيق باستخدام الكاميرا');
    }
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    final school = kind == 'school';
    final schedules = <String, dynamic>{};
    if (school) {
      if (morningDays.union(afternoonDays).union(excluded).length != 7 ||
          morningDays.intersection(afternoonDays).isNotEmpty ||
          morningDays.intersection(excluded).isNotEmpty ||
          afternoonDays.intersection(excluded).isNotEmpty) {
        showAppNotice(context, 'حدد كل يوم: صباحي أو ظهري أو عطلة');
        return;
      }
      for (final group in [morningDays, afternoonDays]) {
        if (group.isEmpty) continue;
        final afternoon = identical(group, afternoonDays);
        final times = afternoon
            ? [afternoonDeparture, afternoonArrival, afternoonReturn]
            : [departure, arrival, returnHome];
        if (times.any((time) => time == null) || !validTimes(times)) {
          showAppNotice(context, 'حدد الانطلاق ثم الوصول ثم الرجوع لكل دوام');
          return;
        }
        for (final day in group)
          schedules['$day'] = {
            'shift': afternoon ? 'afternoon' : 'morning',
            'departure': clock(times[0]!),
            'arrival': clock(times[1]!),
            'return_home': clock(times[2]!),
          };
      }
    }
    if ((!school &&
            (departure == null ||
                arrival == null ||
                returnHome == null ||
                !validTimes([departure, arrival, returnHome]))) ||
        pickup == null ||
        destination == null ||
        front == null ||
        back == null ||
        excluded.length == 7) {
      showAppNotice(context, 'أكمل المواقع والمستمسكات وأوقات الدوام');
      return;
    }
    final firstDate = lineServiceDates(start, 1, excluded).first;
    final firstSchedule = schedules['${firstDate.weekday % 7}'] as Map?;
    setState(() => busy = true);
    try {
      final uid = widget.b.db.auth.currentUser!.id;
      final paths = <String>[];
      for (final entry in [(front!, 'front'), (back!, 'back')]) {
        final bytes = await entry.$1.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024)
          throw Exception('DOCUMENTS_REQUIRED');
        final path = '$uid/$draft/${entry.$2}-${const Uuid().v4()}.jpg';
        await widget.b.db.storage
            .from('tkt-line-documents')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );
        paths.add(path);
      }
      final result = Json.from(
        await lineRpc(widget.b, 'create', {
          'kind': kind,
          'passenger_name': name.text.trim(),
          'pickup_name': pickup!.label,
          'destination_name': destination!.label,
          'pickup_lat': pickup!.point.latitude,
          'pickup_lng': pickup!.point.longitude,
          'destination_lat': destination!.point.latitude,
          'destination_lng': destination!.point.longitude,
          'service_days': int.parse(
            westernDigits(days.text).replaceAll(',', ''),
          ),
          'excluded_days': excluded.toList(),
          'start_date': DateFormat('yyyy-MM-dd').format(start),
          'departure': firstSchedule?['departure'] ?? clock(departure!),
          'arrival': firstSchedule?['arrival'] ?? clock(arrival!),
          'return_home': firstSchedule?['return_home'] ?? clock(returnHome!),
          if (school) 'weekly_schedule': schedules,
          'total_price': int.parse(
            westernDigits(price.text).replaceAll(',', '').replaceAll('٬', ''),
          ),
          'front_path': paths[0],
          'back_path': paths[1],
        }),
      );
      if (mounted)
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => LineDetailPage(b: widget.b, id: result['id']),
          ),
        );
    } catch (e) {
      if (mounted) showAppNotice(context, lineError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool validTimes(List<TimeOfDay?> times) {
    if (times.any((time) => time == null)) return false;
    final minutes = times.map((time) => time!.hour * 60 + time.minute).toList();
    return minutes[0] < minutes[1] && minutes[1] < minutes[2];
  }

  Widget schoolGroup(
    String title,
    Set<int> selected, {
    bool afternoon = false,
    bool holiday = false,
  }) => LineSection(
    title: title,
    icon: holiday ? Icons.event_busy : Icons.schedule,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: List.generate(
          7,
          (day) => FilterChip(
            label: AppText(weekDays[day]),
            selected: selected.contains(day),
            onSelected: busy
                ? null
                : (yes) => setState(() {
                    morningDays.remove(day);
                    afternoonDays.remove(day);
                    excluded.remove(day);
                    if (yes) selected.add(day);
                  }),
          ),
        ),
      ),
      if (!holiday && selected.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final index in [0, 1, 2])
          Builder(
            builder: (context) {
              final times = afternoon
                  ? [afternoonDeparture, afternoonArrival, afternoonReturn]
                  : [departure, arrival, returnHome];
              final value = times[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FormField<TimeOfDay>(
                  key: ValueKey(
                    '$title-$index-${value?.hour}-${value?.minute}',
                  ),
                  initialValue: value,
                  validator: (time) =>
                      time == null ? uiText('حدد الوقت') : null,
                  builder: (field) => InkWell(
                    onTap: busy
                        ? null
                        : () async {
                            final time = await showTimePicker(
                              context: context,
                              initialTime:
                                  value ??
                                  TimeOfDay(
                                    hour: (afternoon
                                        ? [12, 13, 17]
                                        : [7, 8, 12])[index],
                                    minute: 0,
                                  ),
                            );
                            if (mounted && time != null)
                              setState(() {
                                if (afternoon) {
                                  if (index == 0) afternoonDeparture = time;
                                  if (index == 1) afternoonArrival = time;
                                  if (index == 2) afternoonReturn = time;
                                } else {
                                  if (index == 0) departure = time;
                                  if (index == 1) arrival = time;
                                  if (index == 2) returnHome = time;
                                }
                              });
                          },
                    child: InputDecorator(
                      decoration: localizedInput(
                        context,
                        InputDecoration(
                          labelText: [
                            'وقت الانطلاق',
                            'وقت الوصول',
                            'وقت الرجوع للمنزل',
                          ][index],
                          errorText: field.errorText,
                          suffixIcon: const Icon(Icons.access_time),
                        ),
                      ),
                      child: AppText(
                        value == null
                            ? 'حدد الوقت'
                            : clock12(value.hour, value.minute),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final count =
        int.tryParse(westernDigits(days.text).replaceAll(',', '')) ?? 0;
    final dates = count >= 1 && count <= 365 && excluded.length < 7
        ? lineServiceDates(start, count, excluded)
        : <DateTime>[];
    return Scaffold(
      appBar: AppBar(title: const AppText('تسجيل خط')),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            LineSection(
              title: 'نوع ومسار الخط',
              icon: Icons.route,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: localizedInput(
                    context,
                    const InputDecoration(labelText: 'نوع الخط'),
                  ),
                  items: lineKinds.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: AppText(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => kind = v!),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => pick(true),
                  icon: const Icon(Icons.location_on, color: scarlet),
                  label: AppText(
                    pickup?.label ?? 'حدد نقطة الانطلاق على الخريطة',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => pick(false),
                  icon: const Icon(Icons.flag),
                  label: AppText(
                    destination?.label ?? 'حدد نقطة الوصول على الخريطة',
                  ),
                ),
              ],
            ),
            LineSection(
              title: 'أيام الخدمة',
              icon: Icons.calendar_month,
              children: [
                TextFormField(
                  inputFormatters: const [GroupedNumberFormatter()],
                  controller: days,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: localizedInput(
                    context,
                    const InputDecoration(labelText: 'عدد أيام الخدمة'),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    final n = int.tryParse(
                      westernDigits(v ?? '').replaceAll(',', ''),
                    );
                    return n == null || n < 1 || n > 365
                        ? uiText('من 1 إلى 365 يوم')
                        : null;
                  },
                ),
                ListTile(
                  title: const AppText('تاريخ بداية الخط'),
                  subtitle: AppText(DateFormat('yyyy-MM-dd').format(start)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: busy
                      ? null
                      : () async {
                          final now = DateTime.now().toUtc().add(
                            const Duration(hours: 3),
                          );
                          final date = await showDatePicker(
                            context: context,
                            initialDate: start,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (mounted && date != null)
                            setState(() => start = date);
                        },
                ),
                if (kind != 'school') ...[
                  AppText(
                    'الأيام اللي ما يجي بيها الكابتن',
                    style: heading(17),
                  ),
                  Wrap(
                    spacing: 6,
                    children: List.generate(
                      7,
                      (i) => FilterChip(
                        label: AppText(weekDays[i]),
                        selected: excluded.contains(i),
                        onSelected: busy
                            ? null
                            : (yes) => setState(() {
                                if (yes)
                                  excluded.add(i);
                                else
                                  excluded.remove(i);
                              }),
                      ),
                    ),
                  ),
                ],
                const AppText(
                  'الأيام المستبعدة ما تنخصم من عدد أيام الخدمة؛ تاريخ الانتهاء يتمدد تلقائيًا.',
                ),
                if (dates.isNotEmpty)
                  AppText(
                    'آخر يوم خدمة: ${DateFormat('yyyy-MM-dd').format(dates.last)}',
                    style: heading(17),
                  ),
              ],
            ),
            if (kind == 'school') ...[
              schoolGroup('الدوام الصباحي', morningDays),
              schoolGroup('الدوام الظهري', afternoonDays, afternoon: true),
              schoolGroup('أيام العطلة', excluded, holiday: true),
            ],
            if (kind != 'school')
              LineSection(
                title: 'مواعيد الخط',
                icon: Icons.schedule,
                children: [
                  for (final index in [0, 1, 2])
                    Builder(
                      builder: (context) {
                        final value = [departure, arrival, returnHome][index];
                        final label = [
                          'وقت الانطلاق',
                          'وقت الوصول',
                          'وقت الرجوع للمنزل',
                        ][index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FormField<TimeOfDay>(
                            key: ValueKey(
                              '$index-${value?.hour}-${value?.minute}',
                            ),
                            initialValue: value,
                            validator: (v) =>
                                v == null ? uiText('حدد الوقت') : null,
                            builder: (field) => InkWell(
                              onTap: busy
                                  ? null
                                  : () async {
                                      final selected = await showTimePicker(
                                        context: context,
                                        initialTime:
                                            value ??
                                            TimeOfDay(
                                              hour: [7, 8, 14][index],
                                              minute: 0,
                                            ),
                                      );
                                      if (mounted && selected != null)
                                        setState(() {
                                          if (index == 0) departure = selected;
                                          if (index == 1) arrival = selected;
                                          if (index == 2) returnHome = selected;
                                        });
                                    },
                              child: InputDecorator(
                                decoration: localizedInput(
                                  context,
                                  InputDecoration(
                                    labelText: label,
                                    errorText: field.errorText,
                                    suffixIcon: const Icon(Icons.access_time),
                                  ),
                                ),
                                child: AppText(
                                  value == null
                                      ? 'حدد الوقت'
                                      : clock12(value.hour, value.minute),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            LineSection(
              title: 'الأجور والدفع',
              icon: Icons.payments,
              children: [
                TextFormField(
                  inputFormatters: const [GroupedNumberFormatter()],
                  controller: price,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: localizedInput(
                    context,
                    const InputDecoration(
                      labelText: 'كم تريد أن تدفع؟',
                      suffixText: 'د.ع',
                      hintText: 'ما المبلغ الذي تفكر به؟',
                    ),
                  ),
                  validator: (v) {
                    final n = int.tryParse(
                      westernDigits(v ?? '')
                          .replaceAll(',', '')
                          .replaceAll('٬', ''),
                    );
                    return n == null || n < 500 || n > 10000000
                        ? uiText('أدخل مبلغًا صحيحًا بالدينار')
                        : null;
                  },
                ),
                const AppText(
                  'الدفع بنهاية مدة الخط، والسعر المعروض إجمالي كل الأيام.',
                ),
              ],
            ),
            LineSection(
              title: 'بيانات الراكب',
              icon: Icons.person,
              children: [
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  maxLength: 120,
                  decoration: localizedInput(
                    context,
                    const InputDecoration(labelText: 'اسم الراكب الثلاثي'),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().split(RegExp(r'\s+')).length < 3
                      ? uiText('اكتب الاسم الثلاثي')
                      : null,
                ),
              ],
            ),
            LineSection(
              title: 'مستمسكات الراكب',
              icon: Icons.badge,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => photo(true),
                  icon: Icon(
                    front == null ? Icons.camera_alt : Icons.check_circle,
                  ),
                  label: AppText(
                    front == null
                        ? 'صورة الجنسية — الوجه'
                        : 'تم التقاط وجه الجنسية',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => photo(false),
                  icon: Icon(
                    back == null ? Icons.camera_alt : Icons.check_circle,
                  ),
                  label: AppText(
                    back == null
                        ? 'صورة الجنسية — الخلف'
                        : 'تم التقاط خلف الجنسية',
                  ),
                ),
                const AppText(
                  'صور الجنسية محفوظة للمراجعة الإدارية وما تظهر بالكارت أو بعروض الكباتن.',
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : submit,
              child: AppText(busy ? 'جاري التسجيل…' : 'تسجيل الخط'),
            ),
          ],
        ),
      ),
    );
  }
}
