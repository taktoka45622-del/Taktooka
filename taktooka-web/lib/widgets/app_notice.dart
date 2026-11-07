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

final _activeNotices = Expando<VoidCallback>();

void showAppNotice(
  BuildContext context,
  String message, {
  AppNoticeKind? kind,
  ScaffoldMessengerState? messenger,
}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || !overlay.mounted) return;
  _activeNotices[overlay]?.call();
  Timer? lifetime;
  late final OverlayEntry entry;
  var closed = false;
  late final VoidCallback close;
  void release() {
    lifetime?.cancel();
    if (identical(_activeNotices[overlay], close)) {
      _activeNotices[overlay] = null;
    }
  }

  close = () {
    if (closed) return;
    closed = true;
    release();
    if (overlay.mounted) {
      entry.remove();
      entry.dispose();
    }
  };
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      top: MediaQuery.paddingOf(overlayContext).top + kToolbarHeight + 4,
      left: 16,
      right: 16,
      child: _NoticeLifetime(
        onDispose: release,
        child: Material(
          color: Colors.transparent,
          child: Dismissible(
            key: UniqueKey(),
            direction: DismissDirection.up,
            onDismissed: (_) => close(),
            child: AppNotice(message: message, kind: kind, onClose: close),
          ),
        ),
      ),
    ),
  );
  _activeNotices[overlay] = close;
  overlay.insert(entry);
  lifetime = Timer(const Duration(seconds: 5), close);
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
