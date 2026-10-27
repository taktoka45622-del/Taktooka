import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/captain_registration.dart';

class CaptainApplicationBanner extends StatefulWidget {
  final Backend backend;
  final VoidCallback open;
  const CaptainApplicationBanner({
    super.key,
    required this.backend,
    required this.open,
  });
  @override
  State<CaptainApplicationBanner> createState() =>
      _CaptainApplicationBannerState();
}

class _CaptainApplicationBannerState extends State<CaptainApplicationBanner>
    with WidgetsBindingObserver {
  Json? application;
  Timer? timer;
  bool loading = false, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.backend.addListener(changed);
    load();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => load());
  }

  void changed() {
    if (!widget.backend.loggedIn || widget.backend.captain) {
      if (mounted && application != null) setState(() => application = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground) load();
  }

  Future<void> load() async {
    if (loading ||
        !foreground ||
        !widget.backend.loggedIn ||
        widget.backend.captain)
      return;
    loading = true;
    try {
      final uid = widget.backend.db.auth.currentUser?.id;
      final value = await captainRegistration(widget.backend, 'get');
      if (mounted && uid == widget.backend.db.auth.currentUser?.id)
        setState(() => application = value);
      if (value?['status'] == 'approved') await widget.backend.refresh();
    } catch (_) {
    } finally {
      loading = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.backend.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.backend.loggedIn ||
        widget.backend.captain ||
        application?['status'] != 'pending')
      return const SizedBox.shrink();
    final state = application?['status'];
    return Card(
      color: Colors.white,
      child: ListTile(
        onTap: widget.open,
        leading: Icon(
          state == 'changes_required'
              ? Icons.edit_document
              : Icons.assignment_ind_outlined,
          color: const Color(0xffd92527),
        ),
        title: AppText(
          state == 'pending'
              ? 'طلب الكابتن قيد المراجعة'
              : state == 'changes_required'
              ? 'طلب الكابتن يحتاج تعديل'
              : state == 'approved'
              ? 'تمت الموافقة على حساب الكابتن'
              : 'أكمل تسجيل الكابتن',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        subtitle: AppText(
          state == 'changes_required'
              ? '${application!['reason']}'
              : 'اضغط لعرض الطلب ومتابعته',
        ),
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}
