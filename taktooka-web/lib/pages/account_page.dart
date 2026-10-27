import 'package:taktooka/core/numeric_localizations.dart';
import 'package:taktooka/core/display_format.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/account_deletion.dart';
import 'package:taktooka/pages/phone_login_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/profile_photo.dart';
import 'package:taktooka/widgets/profile_photo.dart';

class AccountPage extends StatefulWidget {
  final Backend backend;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;
  final void Function(String) toast;
  const AccountPage({
    super.key,
    required this.backend,
    required this.busy,
    required this.run,
    required this.toast,
  });
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final name = TextEditingController(), phone = TextEditingController();
  final form = GlobalKey<FormState>();
  bool saving = false, photoBusy = false;
  String gender = 'male';
  @override
  void initState() {
    super.initState();
    gender = widget.backend.profile?['gender'] == 'female' ? 'female' : 'male';
    name.text = widget.backend.profile?['name'] ?? '';
    phone.text = widget.backend.profile?['phone'] ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> accountRun(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) widget.toast(readable(e));
    }
  }

  Future<void> choosePhoto() async {
    if (photoBusy || saving) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const AppText('اختيار صورة من الاستوديو'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const AppText('التقاط صورة بالكاميرا'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (widget.backend.profile?['avatar_path'] != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: scarlet),
                title: const AppText('حذف الصورة الشخصية'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => photoBusy = true);
    try {
      await accountRun(() async {
        final b = widget.backend;
        final uid = b.db.auth.currentUser?.id;
        if (uid == null) return;
        final oldPath = b.profile?['avatar_path'] as String?;
        String? path;
        if (choice != 'remove') {
          final file = await ImagePicker().pickImage(
            source: choice == 'camera'
                ? ImageSource.camera
                : ImageSource.gallery,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 90,
          );
          if (file == null) return;
          final bytes = await file.readAsBytes();
          if (bytes.length > 6 * 1024 * 1024)
            throw Exception('اختار صورة أصغر من 6 ميغابايت');
          final compressed = await compressProfilePhoto(bytes);
          if (b.db.auth.currentUser?.id != uid) return;
          path = '$uid/${const Uuid().v4()}.jpg';
          await b.db.storage
              .from('profile-photos')
              .uploadBinary(
                path,
                compressed,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: false,
                ),
              );
        }
        try {
          await b.db.rpc('tkt_profile_photo', params: {'p_path': path});
        } catch (_) {
          if (path != null) {
            try {
              await b.db.storage.from('profile-photos').remove([path]);
            } catch (_) {}
          }
          rethrow;
        }
        if (b.profile != null) b.profile!['avatar_path'] = path;
        if (oldPath != null && oldPath != path) {
          try {
            await b.db.storage.from('profile-photos').remove([oldPath]);
          } catch (_) {}
        }
        unawaited(b.refresh());
        widget.toast(
          choice == 'remove'
              ? 'تم حذف الصورة الشخصية'
              : 'تم حفظ الصورة الشخصية',
        );
      });
    } finally {
      if (mounted) setState(() => photoBusy = false);
    }
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await accountRun(() async {
        await widget.backend.action('profile', {
          'name': name.text.trim(),
          'phone': phone.text.trim(),
          'gender': gender,
        });
        if (widget.backend.profile != null) {
          widget.backend.profile!['name'] = name.text.trim();
          widget.backend.profile!['gender'] = gender;
          accountGender.value = gender;
        }
        unawaited(widget.backend.refresh());
        widget.toast('تم حفظ بياناتك');
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    PreferencesScope.of(context);
    final b = widget.backend;
    if (!b.loggedIn) return PhoneLoginPage(backend: b);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Center(
          child: InkWell(
            onTap: photoBusy || saving ? null : choosePhoto,
            borderRadius: BorderRadius.circular(60),
            child: Stack(
              alignment: Alignment.bottomLeft,
              children: [
                ProfilePhoto(path: b.profile?['avatar_path'], size: 110),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: const BoxDecoration(
                    color: scarlet,
                    shape: BoxShape.circle,
                  ),
                  child: photoBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt_outlined,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: photoBusy || saving ? null : choosePhoto,
          child: const AppText('تعديل الصورة الشخصية'),
        ),
        const SizedBox(height: 18),
        const AppText(
          'بيانات حسابي',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        Form(
          key: form,
          child: Column(
            children: [
              TextFormField(
                inputFormatters: const [EnglishDigitsFormatter()],
                controller: name,
                maxLength: 80,
                decoration: localizedInput(
                  context,
                  InputDecoration(
                    labelText: 'الاسم الكامل',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                validator: (v) => (v?.trim().isNotEmpty ?? false)
                    ? null
                    : uiText('اكتب اسمك', gender: gender),
              ),
              TextFormField(
                inputFormatters: const [EnglishDigitsFormatter()],
                controller: phone,
                readOnly: true,
                textDirection: TextDirection.ltr,
                decoration: localizedInput(
                  context,
                  InputDecoration(
                    labelText: 'رقم الهاتف',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerRight,
                child: AppText(
                  'الجنس',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'male',
                      icon: Icon(Icons.male),
                      label: AppText('ذكر'),
                    ),
                    ButtonSegment(
                      value: 'female',
                      icon: Icon(Icons.female),
                      label: AppText('أنثى'),
                    ),
                  ],
                  selected: {gender},
                  onSelectionChanged: saving || photoBusy
                      ? null
                      : (values) => setState(() => gender = values.single),
                ),
              ),
              const SizedBox(height: 8),
              AppText(
                gender == 'female' ? 'وين تريدين نروح؟' : 'وين تريد نروح؟',
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: saving || photoBusy ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const AppText('حفظ بياناتي'),
                ),
              ),
            ],
          ),
        ),
        if (b.captain)
          AppText(
            'الاشتراك: ${b.subscribed ? displayDateTime(b.profile!['expires_at']) : 'غير فعّال'}',
          ),
        TextButton(
          onPressed: saving || photoBusy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AccountDeletionPage(backend: b),
                  ),
                ),
          child: const AppText(
            'حذف الحساب نهائيًا',
            style: TextStyle(color: scarlet),
          ),
        ),
        TextButton(
          onPressed: saving || photoBusy
              ? null
              : () async {
                  setState(() => saving = true);
                  try {
                    await accountRun(b.signOut);
                  } finally {
                    if (mounted) setState(() => saving = false);
                  }
                },
          child: const AppText('تسجيل خروج'),
        ),
      ],
    );
  }
}
