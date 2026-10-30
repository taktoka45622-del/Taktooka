import 'dart:async';
import 'package:flutter/material.dart';
import 'package:taktooka/core/gender_copy.dart';

enum AppNoticeKind { success, error, warning }

AppNoticeKind noticeKind(String text) {
  final value = text
      .replaceAll('ّ', '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا');
  if ([
    'تعذر',
    'فشل',
    'خطا',
    'غير صحيح',
    'غير صحيحة',
    'محظور',
    'موقوف',
    'تم رفض',
    'لم يتم',
    'لا يمكن',
    'لايمكن',
  ].any(value.contains)) {
    return AppNoticeKind.error;
  }
  if ([
    'الغاء',
    'ملغي',
    'انتظر',
    'حدد',
    'اختر',
    'اسمح',
    'شغل',
    'فعل الموقع',
    'خارج',
    'غير متاح',
    'ماكو',
    'قيد',
    'يرجى',
    'اكمل',
    'متوقف',
    'مطلوب',
    'انتهت',
    'انتهى',
  ].any(value.contains)) {
    return AppNoticeKind.warning;
  }
  if (['تم ', 'بنجاح', 'وصل', 'اكتملت', 'جاهز'].any(value.contains)) {
    return AppNoticeKind.success;
  }
  return AppNoticeKind.warning;
}

final _noticeTimers = Expando<Timer>();

void showAppNotice(
  BuildContext context,
  String message, {
  AppNoticeKind? kind,
  ScaffoldMessengerState? messenger,
}) {
  final host = messenger ?? ScaffoldMessenger.of(context);
  _noticeTimers[host]?.cancel();
  host.clearMaterialBanners();
  host.removeCurrentMaterialBanner();
  Timer? lifetime;
  void close() {
    if (!identical(_noticeTimers[host], lifetime)) return;
    _noticeTimers[host]?.cancel();
    _noticeTimers[host] = null;
    if (host.mounted) host.hideCurrentMaterialBanner();
  }

  host.showMaterialBanner(
    MaterialBanner(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      dividerColor: Colors.transparent,
      padding: const EdgeInsetsDirectional.only(start: 16, top: 4, bottom: 8),
      minActionBarHeight: 0,
      actions: const [SizedBox.shrink()],
      content: _NoticeLifetime(
        onDispose: () {
          lifetime?.cancel();
          if (identical(_noticeTimers[host], lifetime))
            _noticeTimers[host] = null;
        },
        child: AppNotice(message: message, kind: kind, onClose: close),
      ),
    ),
  );
  lifetime = Timer(const Duration(seconds: 5), close);
  _noticeTimers[host] = lifetime;
}

class AppNotice extends StatelessWidget {
  final String message;
  final AppNoticeKind? kind;
  final VoidCallback? onClose;
  const AppNotice({super.key, required this.message, this.kind, this.onClose});

  @override
  Widget build(BuildContext context) {
    final type = kind ?? noticeKind(message);
    final color = switch (type) {
      AppNoticeKind.success => const Color(0xff16865d),
      AppNoticeKind.error => const Color(0xffc92e49),
      AppNoticeKind.warning => const Color(0xffffc43d),
    };
    final foreground = type == AppNoticeKind.warning
        ? const Color(0xff493400)
        : Colors.white;
    final title = switch (type) {
      AppNoticeKind.success => 'تم بنجاح',
      AppNoticeKind.error => 'حدث خطأ',
      AppNoticeKind.warning => 'تنبيه',
    };
    return Semantics(
      liveRegion: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: ColoredBox(
                color: color,
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -48,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .09),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 14,
                      bottom: 49,
                      child: Container(
                        width: 17,
                        height: 17,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .12),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 48),
                              child: AppText(
                                title,
                                textDirection: TextDirection.rtl,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 9),
                            AppText(
                              message,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 17,
            top: 0,
            child: Material(
              color: Color.alphaBlend(
                Colors.black.withValues(alpha: .18),
                color,
              ),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: foreground, size: 25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeLifetime extends StatefulWidget {
  final Widget child;
  final VoidCallback onDispose;
  const _NoticeLifetime({required this.child, required this.onDispose});
  @override
  State<_NoticeLifetime> createState() => _NoticeLifetimeState();
}

class _NoticeLifetimeState extends State<_NoticeLifetime> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
