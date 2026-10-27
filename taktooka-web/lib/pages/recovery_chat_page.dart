import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/phone_auth.dart';

class RecoveryChat extends StatefulWidget {
  final Backend backend;
  final String phone, name;
  final String? adminThread;
  const RecoveryChat({
    super.key,
    required this.backend,
    this.phone = '',
    this.name = '',
    this.adminThread,
  });
  @override
  State<RecoveryChat> createState() => _RecoveryChatState();
}

class _RecoveryChatState extends State<RecoveryChat> {
  final input = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  String? thread, token, error;
  Timer? timer;
  bool reading = false, sending = false;
  bool get admin => widget.adminThread != null;
  @override
  void initState() {
    super.initState();
    start();
    timer = Timer.periodic(const Duration(seconds: 2), (_) { if (mounted && ModalRoute.of(context)?.isCurrent == true && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) unawaited(load()); });
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> start() async {
    try {
      if (admin) {
        thread = widget.adminThread;
      } else {
        final result = await phoneAuth(widget.backend, {
          'op': 'recovery_create',
          'phone': widget.phone,
          'name': widget.name,
        });
        thread = result['thread_id'] as String;
        token = result['token'] as String;
      }
      await load();
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر فتح الدردشة، حاول مرة ثانية');
    }
  }

  Future<void> load() async {
    if (thread == null || reading) return;
    reading = true;
    try {
      final List<dynamic> rows;
      if (admin) {
        rows = await widget.backend.db
            .from('tkt_recovery_messages')
            .select('id,body,is_admin,created_at')
            .eq('thread_id', thread!)
            .order('created_at', ascending: false)
            .limit(200);
      } else {
        final result = await phoneAuth(widget.backend, {
          'op': 'recovery_read',
          'thread_id': thread,
          'token': token,
        });
        rows = (result['messages'] as List).reversed.toList();
      }
      if (mounted)
        setState(() {
          messages = rows
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          error = null;
        });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر تحديث الرسائل');
    } finally {
      reading = false;
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || text.length > 2000 || sending || thread == null) return;
    setState(() => sending = true);
    try {
      final id = const Uuid().v4();
      if (admin) {
        await widget.backend.db.from('tkt_recovery_messages').insert({
          'id': id,
          'thread_id': thread,
          'body': text,
          'is_admin': true,
        });
      } else {
        await phoneAuth(widget.backend, {
          'op': 'recovery_send',
          'thread_id': thread,
          'token': token,
          'body': text,
          'message_id': id,
        });
      }
      input.clear();
      await load();
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر إرسال الرسالة');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('دعم استرجاع الحساب')),
    body: Column(
      children: [
        if (error != null)
          TextButton(
            onPressed: thread == null ? start : load,
            child: AppText(error!),
          ),
        Expanded(
          child: ListView.builder(
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, i) {
              final m = messages[i];
              return Align(
                alignment: m['is_admin'] == true
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: AppText(
                      '${m['is_admin'] == true ? 'الدعم' : 'أنت'}: ${m['body']}',
                    ),
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
                    decoration: localizedInput(
                      context,
                      InputDecoration(
                        hintText: uiText('اكتب رسالتك'),
                        counterText: '',
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: sending || thread == null ? null : send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
