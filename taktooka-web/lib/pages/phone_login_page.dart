import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/privacy_page.dart';
import 'package:taktooka/pages/recovery_chat_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/phone_auth.dart';

class PhoneLoginPage extends StatefulWidget {
  final Backend backend;
  const PhoneLoginPage({super.key, required this.backend});
  @override
  State<PhoneLoginPage> createState() => _PhoneLoginPageState();
}

class _PhoneLoginPageState extends State<PhoneLoginPage> {
  final name = TextEditingController(),
      phone = TextEditingController(),
      password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false,
      passwordStep = false,
      existing = false,
      locked = false,
      visible = false;
  bool privacyAccepted = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  void recover() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => RecoveryChat(
        backend: widget.backend,
        phone: phone.text,
        name: name.text,
      ),
    ),
  );

  Future<void> submit() async {
    if (busy || locked || !form.currentState!.validate()) return;
    if (passwordStep && !existing && !privacyAccepted) {
      setState(
        () =>
            error = 'وافق على سياسة الخصوصية وشروط الاستخدام قبل إنشاء الحساب',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!passwordStep) {
        final result = await phoneAuth(widget.backend, {
          'op': 'probe',
          'phone': phone.text,
        });
        if (!mounted) return;
        setState(() {
          existing = result['exists'] == true;
          locked = result['locked'] == true || result['ambiguous'] == true;
          passwordStep = true;
          if (locked)
            error =
                'الدخول مقفول لهذا الرقم؛ افتح استرجاع الحساب للتواصل مع الدعم';
        });
      } else {
        final result = await phoneAuth(widget.backend, {
          'op': existing ? 'login' : 'register',
          'phone': phone.text,
          'name': name.text.trim(),
          'password': password.text,
          if (!existing) 'privacy_version': privacyVersion,
        });
        await widget.backend.db.auth.setSession(
          result['refresh_token'] as String,
        );
        await widget.backend.refresh().timeout(const Duration(seconds: 20));
      }
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      final code = e.data['error'];
      setState(() {
        if (code == 'ACCOUNT_EXISTS') {
          existing = true;
          error = 'هذا الرقم مسجل؛ اكتب كلمة مرور حسابك';
        } else if (code == 'WRONG_PASSWORD') {
          locked = false;
          error = 'كلمة المرور غير صحيحة، صححها وأعد المحاولة';
        } else if (code == 'LOGIN_LOCKED' || code == 'CONTACT_SUPPORT') {
          locked = true;
          error = 'تقدر تسترجع حسابك من خلال الدعم';
        } else if (code == 'INVALID_PHONE') {
          error = 'اكتب رقم هاتف عراقي صحيح';
        } else if (code == 'ACCOUNT_BLOCKED') {
          error = 'الحساب موقوف، تواصل مع الدعم';
          locked = true;
        } else if (code == 'RATE_LIMIT') {
          error = 'طلبات كثيرة حاليًا، انتظر قليلًا وأعد المحاولة';
          locked = false;
        } else {
          error = 'تعذّر إكمال التسجيل، حاول مرة ثانية';
        }
      });
    } catch (_) {
      if (mounted) setState(() => error = 'تعذّر الاتصال، حاول مرة ثانية');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      AppText(
        passwordStep
            ? (existing ? 'أضف كلمة مرور حسابك' : 'أضف كلمة سر لحسابك')
            : 'تسجيل الدخول',
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 18),
      Form(
        key: form,
        child: Column(
          children: [
            if (!passwordStep) ...[
              TextFormField(
                inputFormatters: const [EnglishDigitsFormatter()],
                controller: name,
                maxLength: 80,
                autofillHints: const [AutofillHints.name],
                decoration: localizedInput(
                  context,
                  InputDecoration(labelText: 'الاسم الكامل'),
                ),
                validator: (v) => (v?.trim().isNotEmpty ?? false)
                    ? null
                    : uiText('اكتب اسمك الكامل'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                inputFormatters: const [EnglishDigitsFormatter()],
                controller: phone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: localizedInput(
                  context,
                  InputDecoration(
                    labelText: 'رقم الهاتف',
                    hintText: '07xxxxxxxxx',
                  ),
                ),
                validator: (v) => (v?.trim().isNotEmpty ?? false)
                    ? null
                    : uiText('اكتب رقم هاتفك'),
              ),
            ] else ...[
              AppText(phone.text, textDirection: TextDirection.ltr),
              const SizedBox(height: 12),
              TextFormField(
                controller: password,
                obscureText: !visible,
                autofillHints: [
                  existing ? AutofillHints.password : AutofillHints.newPassword,
                ],
                decoration: localizedInput(
                  context,
                  InputDecoration(
                    labelText: 'كلمة المرور',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => visible = !visible),
                      icon: Icon(
                        visible ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                ),
                validator: (v) => existing
                    ? ((v?.isNotEmpty ?? false)
                          ? null
                          : uiText('اكتب كلمة المرور'))
                    : ((v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                          ? null
                          : uiText('كلمة السر من ٨ إلى ١٢٨ حرف')),
                onFieldSubmitted: (_) => submit(),
              ),
            ],
            if (passwordStep && !existing)
              CheckboxListTile(
                value: privacyAccepted,
                contentPadding: EdgeInsets.zero,
                title: const AppText(
                  'أوافق على سياسة الخصوصية وشروط الاستخدام',
                ),
                onChanged: busy
                    ? null
                    : (value) =>
                          setState(() => privacyAccepted = value == true),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
              ),
              child: const AppText('سياسة الخصوصية وشروط الاستخدام'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AppText(
                  error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: busy ? null : (locked ? recover : submit),
                child: AppText(
                  busy
                      ? 'لحظة…'
                      : locked
                      ? 'استرجاع الحساب'
                      : passwordStep
                      ? 'دخول'
                      : 'تسجيل',
                ),
              ),
            ),
          ],
        ),
      ),
      if (passwordStep)
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  passwordStep = false;
                  locked = false;
                  error = null;
                  password.clear();
                }),
          child: const AppText('تعديل رقم الهاتف'),
        ),
      if (locked)
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RecoveryChat(
                backend: widget.backend,
                phone: phone.text,
                name: name.text,
              ),
            ),
          ),
          child: const AppText('هل نسيت كلمة السر؟'),
        ),
    ],
  );
}
