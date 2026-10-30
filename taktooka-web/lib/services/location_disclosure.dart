import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/pages/privacy_page.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();
Future<LocationPermission>? _permissionRequest;
Future<bool> locationDisclosure({bool captain = false}) async {
  final prefs = await SharedPreferences.getInstance();
  final key = captain
      ? 'tkt_captain_location_disclosed_v1'
      : 'tkt_location_disclosed_v1';
  if (prefs.getBool(key) == true) return true;
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return false;
  final agreed =
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: AppText(
            captain ? 'مشاركة موقع الكابتن' : 'استخدام الموقع في تكتوكة',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppText(
                captain
                    ? 'عند تفعيل استقبال الطلبات، يرسل تكتوكة موقعك لتوزيع الطلبات ولعرض موقعك للزبون أثناء الرحلة. قد يستمر التحديث بالخلفية عبر خدمة موقع وإشعار ظاهر. أوقف استقبال الطلبات لإيقاف الخدمة، أو غيّر إذن الموقع من إعدادات الجهاز.'
                    : 'يستخدم تكتوكة موقعك الدقيق لتحديد الانطلاق وحساب الطريق. يُستخدم موقع الكابتن لتوزيع الطلبات وتتبع الرحلة، وقد يستمر بالخلفية عند تفعيل استقبال الطلبات مع إشعار ظاهر. تقدر تغيّر الإذن من إعدادات الجهاز.',
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PrivacyPage()),
                ),
                child: const AppText('قراءة سياسة الخصوصية'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const AppText('ليس الآن'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const AppText('متابعة'),
            ),
          ],
        ),
      ) ??
      false;
  if (agreed) await prefs.setBool(key, true);
  return agreed;
}

Future<LocationPermission> requestLocationAccess({
  bool captain = false,
  bool background = false,
}) {
  final pending = _permissionRequest;
  if (pending != null) return pending;
  final request = () async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (captain &&
        background &&
        defaultTargetPlatform == TargetPlatform.android &&
        permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }
    if (captain &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        permission == LocationPermission.whileInUse) {
      try {
        await const MethodChannel(
          'taktooka/location_access',
        ).invokeMethod<void>('requestBackgroundLocation');
      } on MissingPluginException {}
    }
    return permission;
  }();
  _permissionRequest = request;
  return request.whenComplete(() {
    if (identical(_permissionRequest, request)) _permissionRequest = null;
  });
}
