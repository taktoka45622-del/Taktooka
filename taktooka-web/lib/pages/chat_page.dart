import 'package:taktooka/widgets/skeleton.dart';
import 'package:taktooka/services/page_snapshot_cache.dart';
import 'package:taktooka/services/commerce.dart';
import 'package:taktooka/services/food_contact.dart';
import 'package:taktooka/core/numeric_localizations.dart';
import 'package:taktooka/core/display_format.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/refresh_gate.dart';
import 'package:taktooka/widgets/tuktuk_loader.dart';

class ChatPage extends StatefulWidget {
  final Backend b;
  final String? room;
  final String? orderId;
  final String title;
  const ChatPage({
    super.key,
    required this.b,
    this.room,
    this.orderId,
    this.title = 'دعم تكتوكة',
  });
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  final scroll = ScrollController();
  List<Json> messages = [];
  bool sending = false, loading = true;
  String? error, pendingId;
  Json identity = {};
  List<Json> supportOrders = [];
  String? selectedOrder;
  Future<void> loadContext() async {
    try {
      final value = await commerceRpc(widget.b, 'support_context');
      if (mounted && value is Map)
        setState(() {
          identity = Json.from(value);
          supportOrders = Backend.rows(value['orders']);
        });
    } catch (_) {}
  }

  Timer? timer;
  RealtimeChannel? channel;
  final _loadGate = RefreshGate();
  Json get roomData => widget.room == null ? {} : {'user_id': widget.room};
  @override
  void initState() {
    super.initState();
    selectedOrder = widget.orderId;
    final snapshot = PageSnapshotCache.read(
      widget.b,
      'chat:${widget.room ?? "self"}',
    );
    if (snapshot != null) {
      messages = Backend.rows(snapshot['messages']);
      loading = false;
    }
    unawaited(loadContext());
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent == true &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed)
        unawaited(_loadGate.run((_) => _loadOnce(), queue: false));
    });
    channel = widget.b.db
        .channel(
          'tkt-chat-${widget.room ?? widget.b.db.auth.currentUser?.id}-${const Uuid().v4()}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'tkt_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.room ?? widget.b.db.auth.currentUser!.id,
          ),
          callback: (_) => load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    timer?.cancel();
    if (channel != null) widget.b.db.removeChannel(channel!);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() => _loadGate.run((_) => _loadOnce());

  Future<void> _loadOnce() async {
    if (!mounted) return;
    final session = widget.b.cacheEpoch;
    try {
      final wasBottom =
          !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 100;
      final result = Backend.rows(await widget.b.extra('messages', roomData));
      if (!mounted) return;
      if (session != widget.b.cacheEpoch) return;
      PageSnapshotCache.save(widget.b, 'chat:${widget.room ?? "self"}', {
        'messages': result,
      });
      final changed = !sameSnapshot(messages, result);
      final first = loading;
      if (changed || loading || error != null) {
        setState(() {
          messages = result;
          loading = false;
          error = null;
        });
      }
      if (changed && wasBottom) bottom();
      if (changed || first) unawaited(_markRead());
    } catch (e) {
      if (mounted)
        setState(() {
          error = readable(e);
          loading = false;
        });
    }
  }

  Future<void> _markRead() async {
    try {
      await widget.b.extra('read', roomData);
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    }
  }

  void bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients)
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
  });
  Future<void> send() async {
    final body = input.text.trim();
    if (body.isEmpty || sending) return;
    pendingId ??= const Uuid().v4();
    setState(() => sending = true);
    try {
      try {
        await widget.b.db
            .rpc(
              'tkt_support_message',
              params: {
                'p_data': {
                  ...roomData,
                  'body': body,
                  'id': pendingId,
                  if (selectedOrder != null) 'order_id': selectedOrder,
                },
              },
            )
            .timeout(const Duration(seconds: 15));
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202' && e.code != '42883') rethrow;
        final order = supportOrders
            .where((o) => o['id'] == selectedOrder)
            .firstOrNull;
        final detail = order == null ? 'استفسار عام' : foodOrderMessage(order);
        var header =
            '${identity['role'] ?? ''} — ${identity['name'] ?? widget.b.profile?['name'] ?? ''}\n${identity['phone'] ?? widget.b.profile?['phone'] ?? ''}\n$detail';
        if (header.length > 900) header = header.substring(0, 900);
        if (body.length + header.length + 2 > 2000)
          throw StateError('الرسالة طويلة؛ اختصر نص الرسالة إلى 1000 حرف');
        await widget.b.extra('send', {
          ...roomData,
          'body': '$header\n\n$body',
          'id': pendingId,
        });
      }

      if (!mounted) return;
      input.clear();
      pendingId = null;
      await load();
      bottom();
    } catch (e) {
      if (mounted) setState(() => error = readable(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        title: AppText(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const AppText('محادثة خاصة مع الإدارة'),
      ),
      if (identity.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${identity['role'] ?? ''} — ${identity['name'] ?? ''}',
                style: const TextStyle(color: Colors.grey),
              ),
              if (widget.room == null && supportOrders.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  itemHeight: 64,
                  initialValue:
                      supportOrders.any((o) => o['id'] == selectedOrder)
                      ? selectedOrder
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'موضوع المراسلة',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('استفسار عام'),
                    ),
                    for (final o in supportOrders)
                      DropdownMenuItem<String>(
                        value: o['id'],
                        child: Text(
                          'طلب #${foodOrderNumber(o)} — ${o['restaurant_name'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  onChanged: sending
                      ? null
                      : (v) => setState(() => selectedOrder = v),
                ),
            ],
          ),
        ),
      if (loading && messages.isEmpty) const TuktukLoader(),
      if (error != null) TextButton(onPressed: load, child: AppText(error!)),
      Expanded(
        child: ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (_, i) {
            final m = messages[i];
            final own = m['sender_id'] == widget.b.db.auth.currentUser?.id;
            return Align(
              alignment: own ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 300),
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: own
                      ? brandRed
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      m['is_admin'] ? 'الدعم' : 'المستخدم',
                      style: TextStyle(
                        color: own ? Colors.white70 : Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                    if (m['context'] is Map &&
                        (m['context']['subject'] == 'طلب طعام'))
                      Text(
                        'طلب #${foodOrderNumber(m['context']['order'] as Map? ?? {})}',
                        style: TextStyle(
                          color: own ? Colors.white70 : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    AppText(
                      m['body'],
                      style: TextStyle(
                        color: own
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                      ),
                    ),
                    Wrap(
                      children: [
                        for (final phone in foodPhoneNumbers(
                          '${m['body'] ?? ''}',
                        ))
                          TextButton.icon(
                            onPressed: () => openFoodWhatsApp(
                              phone,
                              message: 'تكتوكة\n${m['body'] ?? ''}',
                            ),
                            icon: const Icon(Icons.chat_outlined, size: 17),
                            label: Text('واتساب $phone'),
                            style: TextButton.styleFrom(
                              foregroundColor: own
                                  ? Colors.white
                                  : const Color(0xff128c7e),
                            ),
                          ),
                      ],
                    ),
                    AppText(
                      displayTime(m['created_at']),
                      style: TextStyle(
                        color: own ? Colors.white70 : Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  inputFormatters: const [EnglishDigitsFormatter()],
                  controller: input,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 4,
                  decoration: localizedInput(
                    context,
                    InputDecoration(
                      hintText: uiText('اكتب رسالتك'),
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: sending ? null : send,
                icon: sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: SkeletonActivity(height: 16),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
