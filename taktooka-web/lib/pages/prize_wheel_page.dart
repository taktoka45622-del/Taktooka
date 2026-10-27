import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/models/prize_wheel.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/widgets/wheel_face.dart';

class PrizeWheelPage extends StatefulWidget {
  final Backend backend;
  const PrizeWheelPage({super.key, required this.backend});
  @override
  State<PrizeWheelPage> createState() => _PrizeWheelPageState();
}

class _PrizeWheelPageState extends State<PrizeWheelPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  late final String? _user;
  double _from = 0, _to = 0;
  bool _busy = false, _loading = true, _enabled = true;
  String? _error, _pending;
  DateTime? _nextSpin;
  Duration _serverOffset = Duration.zero;
  Timer? _clock;
  DateTime get _now => DateTime.now().add(_serverOffset);
  bool get _eligible => _nextSpin == null || !_now.isBefore(_nextSpin!);
  void _syncTime(Json value) {
    final server = DateTime.tryParse('${value['server_now']}');
    if (server != null) _serverOffset = server.difference(DateTime.now());
    _nextSpin = DateTime.tryParse('${value['next_spin_at']}');
  }

  Json? _result;
  List<Json> _history = [];
  double get _angle =>
      _from + (_to - _from) * Curves.easeOutCubic.transform(_motion.value);
  String get _pendingKey => 'wheel_pending_$_user';
  @override
  void initState() {
    super.initState();
    _user = widget.backend.db.auth.currentUser?.id;
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _nextSpin != null && !_busy) setState(() {});
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _motion.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    if (mounted) setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      _pending = prefs.getString(_pendingKey);
      final value = Json.from(await widget.backend.wheel('snapshot') as Map);
      if (!mounted) return;
      setState(() {
        _syncTime(value);
        _enabled = value['enabled'] == true;
        _history = Backend.rows(value['history']);
        _error = null;
        _loading = false;
      });
      if (_pending != null) unawaited(_spin());
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString().contains('WHEEL_CAPTAIN_ONLY')
              ? 'العجلة مخصصة للكباتن فقط'
              : readable(e);
          _loading = false;
        });
    }
  }

  Future<void> _spin() async {
    if (_busy || (_pending == null && (!_enabled || !_eligible))) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      if (widget.backend.db.auth.currentUser?.id != _user)
        throw Exception('AUTH_REQUIRED');
      final prefs = await SharedPreferences.getInstance();
      _pending ??= const Uuid().v4();
      await prefs.setString(_pendingKey, _pending!);
      final result = Json.from(
        await widget.backend.wheel('spin', {'id': _pending}) as Map,
      );
      await prefs.remove(_pendingKey);
      _pending = null;
      if (!mounted) return;
      _syncTime(result);
      final key = result['prize_key'] as String?;
      final index = key == null
          ? [1, 3, 5, 7][math.Random().nextInt(4)]
          : wheelResultIndex(key);
      if (index < 0) throw Exception('UNKNOWN_WHEEL_RESULT');
      _from = _angle;
      _to = wheelTargetAngle(_from, index);
      _motion.duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 3000);
      await _motion.forward(from: 0).orCancel;
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _result = result;
        _history = [
          result,
          ..._history.where((x) => x['id'] != result['id']),
        ].take(20).toList();
      });
    } on TickerCanceled {
    } catch (e) {
      if (e.toString().contains('WHEEL_COOLDOWN') ||
          e.toString().contains('WHEEL_PAUSED')) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingKey);
        _pending = null;
        try {
          final current = Json.from(
            await widget.backend.wheel('snapshot') as Map,
          );
          _syncTime(current);
          _enabled = current['enabled'] == true;
        } catch (_) {}
      }
      if (mounted)
        setState(
          () => _error = e.toString().contains('WHEEL_COOLDOWN')
              ? 'تقدر تلف مرة كل 3 أيام'
              : e.toString().contains('WHEEL_PAUSED')
              ? 'العجلة متوقفة مؤقتاً'
              : e.toString().contains('WHEEL_CAPTAIN_ONLY')
              ? 'العجلة مخصصة للكباتن فقط'
              : readable(e),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final won = _result?['prize_key'] != null;
    final remaining = (_nextSpin?.difference(_now).inSeconds ?? 0).clamp(
      0,
      259200,
    );
    final countdown =
        '${(remaining ~/ 3600).toString().padLeft(2, '0')}:${((remaining % 3600) ~/ 60).toString().padLeft(2, '0')}:${(remaining % 60).toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(title: const AppText('عجلة الجوائز')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          AppText('لفّ العجلة وشوف جائزتك', style: heading(26)),
          const SizedBox(height: 6),
          const AppText(
            'اللفة مجانية. إذا توجد جائزة متوفرة تربح جائزة، وإذا ماكو جوائز تطلع حظ أوفر.',
          ),
          const SizedBox(height: 8),
          const AppText('لفة واحدة كل 3 أيام'),
          const SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AspectRatio(
                aspectRatio: 1,
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => WheelFace(angle: _angle),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppText(_error!, style: const TextStyle(color: scarlet)),
            ),
          if (!_enabled && !_loading) const AppText('العجلة متوقفة مؤقتاً'),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _busy || _loading
                  ? null
                  : (_error != null && _pending == null
                        ? () => _load()
                        : ((_enabled && _eligible) || _pending != null
                              ? _spin
                              : null)),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.rotate_right),
              label: AppText(
                _busy
                    ? 'جاري اللف…'
                    : (_pending != null
                          ? 'استرجاع نتيجة اللفة'
                          : (_error != null ? 'إعادة المحاولة' : 'لفّ العجلة')),
              ),
            ),
          ),
          if (!_eligible) ...[
            const SizedBox(height: 10),
            Center(
              child: AppText(
                '${uiText('اللفة القادمة بعد')} $countdown',
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            PaperCard(
              child: Column(
                children: [
                  Icon(
                    won ? Icons.emoji_events : Icons.favorite_border,
                    color: won ? const Color(0xffd09d26) : muted,
                    size: 40,
                  ),
                  AppText(
                    won ? 'مبروك، ربحت جائزة!' : 'حظ أوفر',
                    style: heading(24),
                  ),
                  if (won)
                    AppText(
                      _result!['prize_title'] as String,
                      style: heading(20),
                    ),
                  if (won)
                    const AppText(
                      'جائزتك محفوظة. تواصل مع الدعم لتنسيق الاستلام.',
                    ),
                  if (won)
                    AppText(
                      '#${(_result!['id'] as String).substring(0, 8).toUpperCase()}',
                      textDirection: TextDirection.ltr,
                    ),
                ],
              ),
            ),
          ],
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 22),
            AppText('سجل اللفات والجوائز', style: heading(20)),
            for (final row in _history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row['prize_key'] == null
                      ? Icons.rotate_right
                      : Icons.emoji_events_outlined,
                  color: scarlet,
                ),
                title: AppText(row['prize_title'] as String),
                subtitle: AppText(
                  row['status'] == 'pending'
                      ? 'بانتظار التسليم'
                      : row['status'] == 'delivered'
                      ? 'تم التسليم'
                      : 'حظ أوفر',
                ),
                trailing: AppText(
                  '#${(row['id'] as String).substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontSize: 11),
                  textDirection: TextDirection.ltr,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
