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
  final String title;
  const ChatPage({
    super.key,
    required this.b,
    this.room,
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
  Timer? timer;
  RealtimeChannel? channel;
  final _loadGate = RefreshGate();
  Json get roomData => widget.room == null ? {} : {'user_id': widget.room};
  @override
  void initState() {
    super.initState();
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
    try {
      final wasBottom =
          !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 100;
      final result = Backend.rows(await widget.b.extra('messages', roomData));
      if (!mounted) return;
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
      await widget.b.extra('send', {
        ...roomData,
        'body': body,
        'id': pendingId,
      });
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
      if (loading) const TuktukLoader(),
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
                    AppText(
                      m['body'],
                      style: TextStyle(
                        color: own
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                        fontSize: 16,
                      ),
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
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
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
