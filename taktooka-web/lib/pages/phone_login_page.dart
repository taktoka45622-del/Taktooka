import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:taktooka/core/app_preferences.dart';

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
  final nameFocus = FocusNode(),
  phoneFocus = FocusNode(),
  passwordFocus = FocusNode();
  bool authenticated = false;
  int errorRevision = 0;

  bool busy = false,
  passwordStep = false,
  existing = appPreferences.hasUsedAccount,
  locked = false,
  visible = false;
  bool privacyAccepted = false;
  String? error;
  @override
  void dispose() {
    for (final focus in [nameFocus, phoneFocus, passwordFocus]) {
      focus.dispose();
    }
    name.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  void previousStep() {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
        if (passwordStep) {
          passwordStep = false;
        } else if (!existing) {
          existing = true;
        }
        locked = false;
        visible = false;
        error = null;
    });
  }

  void switchMode() {
    if (busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
        existing = !existing;
        passwordStep = false;
        locked = false;
        visible = false;
        privacyAccepted = false;
        password.clear();
        error = null;
    });
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
    if (busy || locked) return;
    if (!form.currentState!.validate()) {
      setState(() => errorRevision++);
      return;
    }
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
            final found = result['exists'] == true;
            locked = result['locked'] == true || result['ambiguous'] == true;
            if (locked) {
              error =
              'الدخول مقفول لهذا الرقم؛ افتح استرجاع الحساب للتواصل مع الدعم';
            } else if (existing && !found) {
              error = 'هذا الرقم غير مسجل؛ اختر إنشاء حساب';
            } else if (!existing && found) {
              error = 'هذا الرقم مسجل؛ اختر تسجيل الدخول';
            } else {
              passwordStep = true;
            }
        });
      } else {
        final result = await phoneAuth(widget.backend, {
            'op': existing ? 'login' : 'register',
            'phone': phone.text,
            'name': name.text.trim(),
            'password': password.text,
            if (!existing) 'privacy_version': privacyVersion,
        });
        if (!mounted) return;
        setState(() => authenticated = true);
        if (!MediaQuery.disableAnimationsOf(context)) {
          await Future<void>.delayed(const Duration(milliseconds: 320));
        }
        if (!mounted) return;
        await widget.backend.db.auth.setSession(
          result['refresh_token'] as String,
        );
        await appPreferences.rememberAccountUse();
        await widget.backend.refresh().timeout(const Duration(seconds: 20));
      }
    } on PhoneAuthFailure catch (e) {
      if (!mounted) return;
      authenticated = false;
      errorRevision++;
      final code = e.data['error'];
      setState(() {
          if (code == 'ACCOUNT_EXISTS') {
            passwordStep = false;
            error = 'هذا الرقم مسجل؛ اختر تسجيل الدخول';
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
      if (mounted)
      setState(() {
          authenticated = false;
          errorRevision++;
          error = 'تعذّر الاتصال، حاول مرة ثانية';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) previousStep();
    },
    child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity)),
          child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppText(
                    passwordStep
                    ? (existing ? 'أدخل رمز حسابك' : 'إنشاء رمز الحساب')
                    : (existing ? 'تسجيل الدخول' : 'إنشاء حساب'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 18),
                  Form(
                    key: form,
                    child: Column(
                      key: ValueKey('$existing-$passwordStep'),
                      children: [
                        if (!passwordStep) ...[
                          if (!existing) ...[
                            TextFormField(
                              inputFormatters: const [EnglishDigitsFormatter()],
                              controller: name,
                              focusNode: nameFocus,
                              textInputAction: TextInputAction.next,
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
                          ],
                          TextFormField(
                            inputFormatters: const [EnglishDigitsFormatter()],
                            controller: phone,
                            focusNode: phoneFocus,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => submit(),
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
                            validator: (v) {
                              final value = (v ?? '').trim().replaceAll(
                                RegExp(r'[\s()-]'),
                                '',
                              );
                              return RegExp(
                                r'^(07\d{9}|(?:\+964|00964|964)7\d{9})$',
                              ).hasMatch(value)
                              ? null
                              : uiText('اكتب رقم هاتف عراقي صحيح');
                            },
                          ),
                        ] else ...[
                          AppText(phone.text, textDirection: TextDirection.ltr),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: password,
                            focusNode: passwordFocus,
                            textInputAction: TextInputAction.done,
                            obscureText: !visible,
                            autofillHints: [
                              existing
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                            ],
                            decoration: localizedInput(
                              context,
                              InputDecoration(
                                labelText: existing ? 'رمز الحساب' : 'إنشاء رمز الحساب',
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
                              : uiText('اكتب رمز حسابك'))
                            : ((v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                              ? null
                              : uiText('رمز الحساب من 8 إلى 128 حرف')),
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
                              ? (existing ? 'دخول' : 'إنشاء حساب')
                              : 'التالي',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : switchMode,
                    child: AppText(
                      existing ? 'ليس لدي حساب — إنشاء حساب' : 'لدي حساب — تسجيل الدخول',
                    ),
                  ),
                  if (passwordStep || !existing)
                  TextButton(
                    onPressed: busy ? null : previousStep,
                    child: const AppText('رجوع'),
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
              ),
          )),
        ),
    )),
  );
}
