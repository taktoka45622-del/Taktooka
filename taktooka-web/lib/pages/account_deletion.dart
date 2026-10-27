import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/phone_auth.dart';

class AccountDeletionPage extends StatefulWidget {
  final Backend backend;
  const AccountDeletionPage({super.key, required this.backend});
  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  final password = TextEditingController();
  bool agreed = false, busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> remove() async {
    if (!agreed || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final b = widget.backend;
    try {
      final state = await b.db.functions.invoke(
        'taktooka-account-delete',
        body: {'op': 'status'},
      );
      if (state.data?['status'] == null) {
        if (password.text.isEmpty)
          throw Exception('اكتب كلمة المرور لتأكيد ملكية الحساب');
        final login = await phoneAuth(b, {
          'op': 'login',
          'phone': b.profile?['phone'],
          'password': password.text,
        });
        await b.db.auth.setSession(login['refresh_token']);
      }
      final result = await b.db.functions.invoke(
        'taktooka-account-delete',
        body: {'confirm': 'DELETE_ACCOUNT'},
      );
      if (result.data?['ok'] != true) throw Exception('تعذّر إكمال حذف الحساب');
      await b.signOut();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText('تم حذف حساب تكتوكة وبياناته الشخصية'),
          ),
        );
      }
    } catch (e) {
      final data = e is FunctionException
          ? e.details
          : e is PhoneAuthFailure
          ? e.data
          : null;
      final code = data is Map ? data['error'] : null;
      final message = switch (code) {
        'ACTIVE_RIDE' => 'أنه أو ألغِ الرحلة الحالية قبل حذف الحساب.',
        'SETTLE_BALANCE' =>
          'تواصل مع الدعم لتسوية الرصيد أو المستحقات أولًا، ثم أعد الحذف.',
        'PROTECTED_ADMIN' =>
          'هذا حساب إدارة؛ يلزم نقل صلاحيات الإدارة قبل حذفه.',
        'WRONG_PASSWORD' => 'كلمة المرور غير صحيحة.',
        'REAUTH_REQUIRED' => 'أعد تسجيل الدخول لتأكيد ملكية الحساب.',
        'DELETE_PENDING_RETRY' =>
          'الحذف قيد الإكمال؛ اضغط مجددًا لإعادة المحاولة. لا تنشئ حسابًا جديدًا الآن.',
        _ =>
          'تعذّر إكمال الحذف. تأكد من كلمة المرور والاتصال أو تواصل مع الدعم.',
      };
      if (mounted) setState(() => error = message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('حذف الحساب')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(
          child: CategoryIcon(Icons.delete_outline, size: 70, circle: true),
        ),
        const SizedBox(height: 16),
        AppText('حذف حساب تكتوكة نهائيًا', style: heading(23)),
        const SizedBox(height: 12),
        const AppText(
          'تُحذف بيانات الحساب الشخصية والصور ومستندات الكابتن والرسائل والعناوين والموقع. قد تبقى سجلات مالية محدودة دون الاسم ورقم الهاتف للتسويات ومنع الاحتيال. يلزم إنهاء أو إلغاء الرحلة الحالية وتسوية الرصيد قبل الحذف. لا يمكن استعادة الحساب المحذوف.',
          style: TextStyle(height: 1.8),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: password,
          obscureText: true,
          decoration: localizedInput(
            context,
            InputDecoration(labelText: 'كلمة المرور لتأكيد ملكية الحساب'),
          ),
        ),
        CheckboxListTile(
          value: agreed,
          onChanged: busy
              ? null
              : (value) => setState(() => agreed = value == true),
          contentPadding: EdgeInsets.zero,
          title: const AppText(
            'أفهم أن الحذف نهائي وأريد حذف حسابي وبياناته الشخصية',
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: AppText(error!, style: const TextStyle(color: scarlet)),
          ),
        FilledButton(
          onPressed: agreed && !busy ? remove : null,
          child: AppText(busy ? 'جاري حذف الحساب…' : 'حذف الحساب نهائيًا'),
        ),
      ],
    ),
  );
}
