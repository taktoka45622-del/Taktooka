import 'package:taktooka/core/numeric_localizations.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/verification_flow/capture_page.dart'
    if (dart.library.js_interop) 'package:taktooka/pages/verification_flow/capture_page_web.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/captain_registration.dart';
import 'package:taktooka/widgets/flip_card_hint.dart';

class CaptainRegistrationPage extends StatefulWidget {
  final Backend backend;
  const CaptainRegistrationPage({super.key, required this.backend});
  @override
  State<CaptainRegistrationPage> createState() =>
      _CaptainRegistrationPageState();
}

class _CaptainRegistrationPageState extends State<CaptainRegistrationPage>
    with WidgetsBindingObserver {
  final province = TextEditingController(), area = TextEditingController();
  final name = TextEditingController(),
      phone = TextEditingController(),
      chassis = TextEditingController(),
      color = TextEditingController(),
      model = TextEditingController();
  final picker = ImagePicker();
  final Map<String, String> previews = {};
  Json? application;
  bool loading = true, busy = false, foreground = true;
  int step = 0;
  String? error;
  Timer? timer;
  Backend get b => widget.backend;
  bool get locked => ['pending', 'approved'].contains(application?['status']);
  Json get documents => Json.from(application?['documents'] as Map? ?? {});
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load(initial: true);
    timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (locked && foreground) load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && locked) load();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [name, phone, chassis, color, model, province, area]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load({bool initial = false}) async {
    if (busy) return;
    busy = true;
    try {
      application = await captainRegistration(b, 'get');
      if (!mounted) return;
      if (initial) {
        name.text = application?['full_name'] ?? b.profile?['name'] ?? '';
        province.text = application?['province'] ?? b.city;
        area.text = application?['area'] ?? '';
        final savedPhone = application?['phone']?.toString() ?? '';
        phone.text = b.profile?['phone']?.toString() ?? savedPhone;
        chassis.text = application?['chassis'] ?? '';
        color.text = application?['color'] ?? '';
        model.text = application?['model'] ?? '';
        final lost = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? await picker.retrieveLostData()
            : LostDataResponse.empty();
        final slot = application?['pending_slot'] as String?;
        if (!locked && lost.files?.isNotEmpty == true && slot == 'portrait') {
          if (!await validPersonalPhoto(lost.files!.first))
            throw Exception('FACE_REQUIRED');
          await upload(
            slot!,
            lost.files!.first,
            checks: {'profile_single_face': true},
          );
        }
        if (lost.exception != null)
          error = captainRegistrationError(lost.exception!);
      }
      if (!locked) await loadPreviews();
      if (application?['status'] == 'approved') await b.refresh();
    } catch (e) {
      error = captainRegistrationError(e);
    } finally {
      if (mounted)
        setState(() {
          loading = false;
          busy = false;
        });
    }
  }

  Future<void> loadPreviews() async {
    await Future.wait(
      documents.keys.map((slot) async {
        try {
          previews[slot] = await b.db.storage
              .from('captain-documents')
              .createSignedUrl(documents[slot] as String, 3600);
        } catch (_) {
          previews.remove(slot);
        }
      }),
    );
  }

  Json fields() => {
    'full_name': name.text.trim(),
    'province': province.text.trim(),
    'area': area.text.trim(),
    'phone': phone.text.trim(),
    'chassis': chassis.text.trim(),
    'color': color.text.trim(),
    'model': model.text.trim(),
  };
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      error = captainRegistrationError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload(String slot, XFile file, {Json? checks}) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.length > 6 * 1024 * 1024) throw StateError('INVALID_DOCUMENT');
    String mime = 'image/jpeg', extension = 'jpg';
    if (bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      mime = 'image/png';
      extension = 'png';
    } else if (bytes.length > 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45) {
      mime = 'image/webp';
      extension = 'webp';
    } else if (bytes.length < 3 || bytes[0] != 0xff || bytes[1] != 0xd8) {
      throw StateError('INVALID_DOCUMENT');
    }
    final path = '${b.db.auth.currentUser!.id}/${const Uuid().v4()}.$extension';
    final oldPath = documents[slot] as String?;
    await b.db.storage
        .from('captain-documents')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    try {
      application = await captainRegistration(b, 'save', {
        'document': {'slot': slot, 'path': path},
        if (checks != null) 'verification': checks,
      });
    } catch (_) {
      try {
        await b.db.storage.from('captain-documents').remove([path]);
      } catch (_) {}
      rethrow;
    }
    if (oldPath != null && oldPath != path) {
      try {
        await b.db.storage.from('captain-documents').remove([oldPath]);
      } catch (_) {}
    }
    previews[slot] = await b.db.storage
        .from('captain-documents')
        .createSignedUrl(path, 3600);
  }

  void pick(String slot) => run(() async {
    if (kIsWeb) {
      application = await captainRegistration(b, 'save', fields());
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file != null) await upload(slot, file);
      return;
    }
    application = await captainRegistration(b, 'save', {
      ...fields(),
      'pending_slot': slot,
    });
    if (!mounted) return;
    if (slot == 'portrait') {
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
        requestFullMetadata: false,
      );
      if (file != null) {
        if (!await validPersonalPhoto(file)) throw StateError('FACE_REQUIRED');
        await upload(slot, file, checks: {'profile_single_face': true});
      } else {
        application = await captainRegistration(b, 'save', {
          'pending_slot': null,
        });
      }
    } else {
      final result = await Navigator.of(context).push<CaptureResult>(
        MaterialPageRoute(
          builder: (_) => CapturePage(
            title: captainDocumentLabels[slot] ?? 'صورة المستمسك',
            face: slot == 'selfie',
          ),
        ),
      );
      if (result != null)
        await upload(
          slot,
          result.file,
          checks: slot == 'selfie' ? result.checks : null,
        );
      else
        application = await captainRegistration(b, 'save', {
          'pending_slot': null,
        });
    }
  });
  Future<void> next() async {
    await run(() async {
      if (step == 0) {
        if (name.text.trim().split(RegExp(r'\s+')).length < 3)
          throw StateError('FULL_NAME_REQUIRED');
        if (province.text.trim().isEmpty || area.text.trim().isEmpty)
          throw StateError('AREA_REQUIRED');
      } else if (documents[step == 1 ? 'id_front' : 'id_back'] == null)
        throw StateError('DOCUMENTS_REQUIRED');
      application = await captainRegistration(b, 'save', fields());
      if (mounted) setState(() => step++);
    });
  }

  void submit() => run(() async {
    if (documents['id_front'] == null || documents['id_back'] == null)
      throw StateError('DOCUMENTS_REQUIRED');
    application = await captainRegistration(b, 'save', fields());
    application = await captainRegistration(b, 'submit');
    await b.refresh();
  });
  Widget field(
    String label,
    TextEditingController controller, {
    bool tel = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      inputFormatters: const [EnglishDigitsFormatter()],
      controller: controller,
      enabled: !busy && !locked,
      keyboardType: tel ? TextInputType.phone : TextInputType.text,
      maxLength: tel ? 20 : 160,
      decoration: localizedInput(
        context,
        InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          counterText: '',
        ),
      ),
    ),
  );
  Widget photo(String slot) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppText(
        captainDocumentLabels[slot] ?? 'صورة المستمسك',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      if (previews[slot] != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            previews[slot]!,
            height: 220,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const AppText('تعذّر عرض الصورة؛ حدّث الصفحة'),
          ),
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: busy ? null : () => pick(slot),
        icon: Icon(
          slot == 'portrait'
              ? Icons.photo_library_outlined
              : Icons.camera_alt_outlined,
        ),
        label: AppText(
          slot == 'portrait'
              ? 'إضافة صورة شخصية للبروفايل'
              : documents[slot] == null
              ? 'فتح الكاميرا والتقاط الصورة'
              : 'إعادة التقاط الصورة',
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('تسجيل كابتن')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () => load(),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null) ...[
                  AppText(error!, style: const TextStyle(color: Colors.red)),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => load(initial: application == null),
                    child: const AppText('إعادة المحاولة'),
                  ),
                ],
                if (busy) const LinearProgressIndicator(),
                if (locked) ...[
                  Icon(
                    application?['status'] == 'approved'
                        ? Icons.verified
                        : Icons.hourglass_top,
                    size: 64,
                    color: const Color(0xffd92527),
                  ),
                  const SizedBox(height: 20),
                  AppText(
                    application?['status'] == 'approved'
                        ? 'تمت الموافقة على حساب الكابتن'
                        : 'طلبك قيد المراجعة',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppText(
                    '${application?['full_name']}\n${application?['province']} — ${application?['area']}\nراح يوصلك إشعار من تتم الموافقة على طلبك.',
                  ),
                  if (application?['status'] == 'approved')
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const AppText('فتح حساب الكابتن'),
                    ),
                ] else ...[
                  if (application?['status'] == 'changes_required')
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: AppText(
                          'التعديل المطلوب:\n${application!['reason']}',
                          style: const TextStyle(
                            color: Color(0xffd92527),
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ),
                  AppText(
                    'الخطوة ${step + 1} من 4',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 16),
                  if (step == 0) ...[
                    field('الاسم الكامل', name),
                    DropdownButtonFormField<String>(
                      initialValue: iraqProvinces.contains(province.text)
                          ? province.text
                          : null,
                      decoration: localizedInput(
                        context,
                        InputDecoration(labelText: 'المحافظة'),
                      ),
                      items: [
                        for (final v in iraqProvinces)
                          DropdownMenuItem(value: v, child: AppText(v)),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              province.text = v ?? '';
                            },
                    ),
                    const SizedBox(height: 16),
                    field('المنطقة', area),
                  ],
                  if (step == 2) const FlipCardHint(),
                  if (step == 1 || step == 2)
                    photo(step == 1 ? 'id_front' : 'id_back'),
                  if (step == 3) ...[
                    PaperCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppText(name.text, style: heading(20)),
                          AppText('${province.text} — ${area.text}'),
                          const SizedBox(height: 12),
                          const AppText(
                            'سيتم إرسال بياناتك وصورتي الجنسية للإدارة لمراجعة طلب تسجيلك.',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (step > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => step--),
                            child: const AppText('السابق'),
                          ),
                        ),
                      if (step > 0) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: busy
                              ? null
                              : step == 3
                              ? submit
                              : next,
                          child: AppText(step == 3 ? 'إرسال الطلب' : 'التالي'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
  );
}
