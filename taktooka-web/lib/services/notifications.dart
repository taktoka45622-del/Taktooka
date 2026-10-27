import 'package:taktooka/services/web_push_stub.dart'
    if (dart.library.js_interop) 'package:taktooka/services/web_push_browser.dart';
import 'package:taktooka/core/display_format.dart';
import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/core/firebase_options.dart';
import 'package:taktooka/services/backend.dart';

Duration offerRingDuration(DateTime? expires, {DateTime? now}) {
  final left =
      expires?.difference(now ?? DateTime.now()).inMilliseconds ?? 30000;
  return Duration(milliseconds: left.clamp(0, 30000));
}

int noticeId(String value) {
  var n = 0;
  for (final c in value.codeUnits) {
    n = (n * 31 + c) & 0x7fffffff;
  }
  return n;
}

bool noticeExpired(Map<String, dynamic> n) =>
    DateTime.tryParse('${n['expires_at']}')?.isBefore(DateTime.now().toUtc()) ??
    false;
Map<String, dynamic> noticeData(Map<String, dynamic> n) => {
  ...n,
  ...?n['target'] as Map<String, dynamic>?,
};
final nativeNotices = FlutterLocalNotificationsPlugin();
const appleNotices = MethodChannel('taktooka/notifications');
Future<void> cancelAppleOffer(String id) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    await appleNotices.invokeMethod<void>('cancelOffer', id);
  } on MissingPluginException {}
}

Future<void> noticeQueue = Future.value();
Future<void> displayNotice(Map<String, dynamic> raw, {bool ring = true}) {
  noticeQueue = noticeQueue
      .catchError((_) {})
      .then((_) => _displayNotice(raw, ring: ring));
  return noticeQueue;
}

Future<void> setupNative({void Function(NotificationResponse)? onTap}) async {
  if (kIsWeb) return;
  await nativeNotices.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestSoundPermission: false,
        requestBadgePermission: false,
      ),
    ),
    onDidReceiveNotificationResponse: onTap,
  );
}

Future<void> _displayNotice(
  Map<String, dynamic> raw, {
  bool ring = true,
}) async {
  if (kIsWeb) return;
  final n = noticeData(raw),
      offer = n['kind'] == 'offer',
      id = noticeId(
        '${offer || n['kind'] == 'offer_end' ? n['offer_id'] : n['notification_id'] ?? n['id']}',
      );
  if (n['kind'] == 'offer_end') {
    await cancelAppleOffer('${n['offer_id']}');
    await nativeNotices.cancel(id);
    return;
  }
  if (noticeExpired(n)) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (prefs.getString('notice_user') != n['recipient_id'] &&
      prefs.getString('notice_user') != n['user_id'])
    return;
  final key = 'notice_seen_${prefs.getString('notice_user')}',
      seen = prefs.getStringList(key) ?? [];
  final event = '${n['notification_id'] ?? n['id']}';
  if (seen.contains(event)) return;
  seen.add(event);
  await nativeNotices.show(
    id,
    englishDigits('${n['title'] ?? 'تكتوكة'}'),
    englishDigits('${n['body'] ?? ''}'),
    NotificationDetails(
      android: AndroidNotificationDetails(
        offer ? 'tkt_requests_v3' : 'tkt_updates_v1',
        offer ? 'طلبات المشاوير' : 'تحديثات تكتوكة',
        channelDescription: offer
            ? 'طلبات الكابتن مع جرس حتى 30 ثانية'
            : 'الرحلات والدعم والمحفظة والحساب',
        importance: Importance.max,
        priority: Priority.high,
        playSound: ring,
        sound: offer
            ? const RawResourceAndroidNotificationSound('captain_request')
            : null,
        timeoutAfter: offer
            ? offerRingDuration(
                DateTime.tryParse('${n['expires_at']}'),
              ).inMilliseconds
            : null,
        additionalFlags: offer && ring ? Int32List.fromList([4]) : null,
        autoCancel: true,
        category: AndroidNotificationCategory.message,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: ring,
        sound: offer && ring ? 'captain_request.caf' : null,
      ),
    ),
    payload: jsonEncode(n),
  );
  await prefs.setStringList(
    key,
    seen.length > 200 ? seen.sublist(seen.length - 200) : seen,
  );
}

@pragma('vm:entry-point')
Future<void> firebaseBackground(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: TaktookaFirebaseOptions.currentPlatform,
    );
    await setupNative();
    if (defaultTargetPlatform == TargetPlatform.android ||
        message.data['kind'] == 'offer_end')
      await displayNotice(message.data);
  } catch (_) {}
}

class NotificationCenter extends ChangeNotifier {
  final Backend backend;
  final void Function(Json) open;
  NotificationCenter(this.backend, this.open, {AudioPlayer? audioPlayer})
    : player = audioPlayer ?? AudioPlayer() {
    backend.enableOrderNotifications = () => enableDeviceNotifications();
  }
  List<Json> inbox = [];
  String? user, token;
  Json? pending;
  String? deviceError, inboxError;
  bool nativeReady = false,
      deviceRegistered = false,
      permissionDenied = false,
      connecting = false,
      loadedInbox = false;
  DateTime? lastDeviceAttempt;
  bool firebaseReady = false,
      foreground = true,
      loading = false,
      closed = false;
  RealtimeChannel? channel;
  StreamSubscription? auth, tokenRefresh, foregroundMessages, openedMessages;
  Timer? poll, ringTimer;
  final AudioPlayer player;
  final Set<String> rung = {};
  String? ringing;
  Future<void> audioQueue = Future.value(), binding = Future.value();
  int get unread => inbox
      .where((n) => n['read_at'] == null && n['kind'] != 'offer_end')
      .length;
  Future<void> requestStartupPermission() async {
    if (kIsWeb || closed) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await nativeNotices
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        await nativeNotices
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (error) {
      deviceError = describeDeviceError(error);
    }
  }

  Future<void> start() async {
    try {
      await setupNative(
        onTap: (response) {
          try {
            tap(Json.from(jsonDecode(response.payload ?? '{}') as Map));
          } catch (_) {}
        },
      );
      nativeReady = true;
      final launch = kIsWeb
          ? null
          : await nativeNotices.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        try {
          pending = Json.from(
            jsonDecode(launch!.notificationResponse?.payload ?? '{}') as Map,
          );
        } catch (_) {}
      }
    } catch (error) {
      deviceError = describeDeviceError(error);
    }
    if (kIsWeb) {
      listenWebPush((value, clicked) {
        if (clicked) {
          tap(value);
        } else {
          receive(value);
        }
      });
    }
    await initializeFirebase();
    backend.beforeSignOut = unbind;
    backend.silenceOffer = silenceOffer;
    backend.addListener(changed);
    auth = backend.db.auth.onAuthStateChange.listen((_) {
      changed();
    });
    poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (foreground) {
        unawaited(load());
        if (!deviceRegistered &&
            !connecting &&
            (lastDeviceAttempt == null ||
                DateTime.now().difference(lastDeviceAttempt!).inSeconds >=
                    60)) {
          unawaited(enableDeviceNotifications(requestPermission: false));
        }
      }
    });
    changed();
  }

  String describeDeviceError(Object error) {
    debugPrint('Taktooka notification setup failed: $error');
    if (error is PlatformException) {
      if (error.code == 'invalid_icon' || error.code == 'invalid_sound') {
        return 'تعذّر تحميل أيقونة أو صوت الإشعارات (${error.code}). ثبّت نسخة التطبيق المحدّثة ثم أعد المحاولة.';
      }
      return 'تعذّر تفعيل إشعارات الجهاز (${error.code}): ${error.message ?? 'أعد المحاولة'}';
    }
    final code = error is FirebaseException
        ? error.code
        : error.runtimeType.toString();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'تعذّر تفعيل إشعارات الآيفون ($code). تحقق من الإنترنت وإذن الإشعارات وإعداد Firebase وAPNs.';
    }
    return 'تعذّر تفعيل إشعارات الجهاز ($code). تأكد من الإنترنت وخدمات Google Play، ثم أعد المحاولة.';
  }

  Future<void> initializeFirebase() async {
    if (kIsWeb || closed || firebaseReady) return;
    try {
      await Firebase.initializeApp(
        options: TaktookaFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 15));
      FirebaseMessaging.onBackgroundMessage(firebaseBackground);
      foregroundMessages ??= FirebaseMessaging.onMessage.listen(
        (m) => receive(m.data),
      );
      openedMessages ??= FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => tap(m.data),
      );
      tokenRefresh ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (value) {
          token = value;
          unawaited(register());
        },
        onError: (Object error) {
          deviceRegistered = false;
          deviceError = describeDeviceError(error);
          if (!closed) notifyListeners();
        },
      );
      firebaseReady = true;
      deviceError = null;
      try {
        final initial = await FirebaseMessaging.instance
            .getInitialMessage()
            .timeout(const Duration(seconds: 5));
        if (initial != null) pending = initial.data;
      } catch (_) {}
    } catch (error) {
      firebaseReady = false;
      deviceError = describeDeviceError(error);
    }
  }

  Future<void> enableDeviceNotifications({
    bool requestPermission = true,
  }) async {
    if (closed || connecting || user == null) return;
    if (kIsWeb) {
      connecting = true;
      lastDeviceAttempt = DateTime.now();
      final uid = user;
      try {
        final value = await requestWebPush(requestPermission);
        if (uid != user || closed) return;
        if (value != null && value.isNotEmpty) {
          token = value;
          await register();
        }
      } catch (_) {
        deviceRegistered = false;
        deviceError =
            'تعذر تفعيل إشعارات المتصفح. اسمح بالإشعارات وافتح الموقع بمتصفح يدعمها مثل Chrome.';
      } finally {
        connecting = false;
        if (!closed) notifyListeners();
      }
      return;
    }
    connecting = true;
    lastDeviceAttempt = DateTime.now();
    deviceRegistered = false;
    if (!closed) notifyListeners();
    final uid = user;
    try {
      if (!nativeReady) {
        await setupNative(
          onTap: (response) {
            try {
              tap(Json.from(jsonDecode(response.payload ?? '{}') as Map));
            } catch (_) {}
          },
        );
        nativeReady = true;
      }
      await initializeFirebase();
      if (!firebaseReady) return;
      final settings = requestPermission
          ? await FirebaseMessaging.instance.requestPermission(
              alert: true,
              badge: true,
              sound: true,
            )
          : await FirebaseMessaging.instance.getNotificationSettings();
      permissionDenied =
          settings.authorizationStatus == AuthorizationStatus.denied;
      if (permissionDenied) {
        deviceError =
            'إشعارات الجهاز متوقفة. اسمح بها من إعدادات الهاتف ← التطبيقات ← تكتوكة ← الإشعارات.';
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns;
        for (
          var attempt = 0;
          attempt < 20 && !closed && uid == user;
          attempt++
        ) {
          apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (apns == null) throw StateError('APNS_TOKEN_UNAVAILABLE');
      }
      token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 15),
      );
      if (uid != user || closed) return;
      if (token == null) throw StateError('FCM_TOKEN_UNAVAILABLE');
      await register();
    } catch (error) {
      deviceError = describeDeviceError(error);
    } finally {
      connecting = false;
      if (!closed) notifyListeners();
    }
  }

  void changed() {
    final uid = backend.db.auth.currentUser?.id;
    if (uid != user) {
      binding = binding.catchError((_) {}).then((_) => bind(uid));
    }
    syncOffers();
  }

  Future<void> bind(String? uid) async {
    if (closed || backend.db.auth.currentUser?.id != uid || uid == user) return;
    await unbind();
    if (closed || uid == null || backend.db.auth.currentUser?.id != uid) return;
    user = uid;
    await (await SharedPreferences.getInstance()).setString('notice_user', uid);
    channel =
        backend.db
            .channel('tkt-notice-$uid')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'tkt_notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: uid,
              ),
              callback: (p) => receive(p.newRecord),
            )
          ..subscribe();
    await load();
    await enableDeviceNotifications(requestPermission: false);
    if (pending != null) {
      final n = pending!;
      pending = null;
      tap(n);
    }
  }

  Future<dynamic> rpc(String action, [Json data = const {}]) => backend.db.rpc(
    'tkt_notification_action',
    params: {'p_action': action, 'p_data': data},
  );
  Future<void> register() async {
    final uid = user, deviceToken = token;
    if (uid == null || deviceToken == null) return;
    try {
      await rpc('register', {
        'token': deviceToken,
        'platform': kIsWeb
            ? 'web'
            : defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      });
      if (uid != user || closed) return;
      deviceRegistered = true;
      deviceError = null;
    } catch (error) {
      if (uid != user || closed) return;
      deviceRegistered = false;
      deviceError =
          'تعذّر تسجيل الجهاز بالسيرفر. تأكد من الاتصال واضغط إعادة المحاولة.';
    }
    if (!closed) notifyListeners();
  }

  Future<void> unbind() async {
    try {
      await stopRing();
    } catch (_) {}
    try {
      if (nativeReady) await nativeNotices.cancelAll();
    } catch (_) {}
    if (token != null && user == backend.db.auth.currentUser?.id) {
      try {
        await rpc('unregister', {'token': token});
      } catch (_) {}
    }
    if (channel != null) {
      await backend.db.removeChannel(channel!);
      channel = null;
    }
    user = null;
    deviceRegistered = false;
    loadedInbox = false;
    inboxError = null;
    inbox = [];
    rung.clear();
    await (await SharedPreferences.getInstance()).remove('notice_user');
    if (!closed) notifyListeners();
  }

  Future<void> load() async {
    final uid = user;
    if (uid == null || loading || closed) return;
    loading = true;
    try {
      final values = Backend.rows(await rpc('list'));
      if (uid != user || closed) return;
      final previous = inbox.map((n) => n['id']).toSet();
      final incoming = loadedInbox
          ? values.where((n) => !previous.contains(n['id'])).toList()
          : <Json>[];
      inbox = values;
      loadedInbox = true;
      inboxError = null;
      for (final n in incoming.reversed) {
        receive(n);
      }
      notifyListeners();
    } catch (_) {
      inboxError = 'تعذّر تحميل سجل الإشعارات. اسحب الصفحة لإعادة المحاولة.';
      if (!closed) notifyListeners();
    } finally {
      loading = false;
    }
  }

  Future<void> showDeviceNotice(Json n, {bool ring = true}) async {
    if (!nativeReady) return;
    try {
      await displayNotice(n, ring: ring);
    } catch (error) {
      deviceError = describeDeviceError(error);
      if (!closed) notifyListeners();
    }
  }

  void receive(Map<String, dynamic> value) {
    final n = noticeData(value), recipient = n['recipient_id'] ?? n['user_id'];
    if (recipient != user || closed) return;
    if (n['kind'] == 'offer_end') {
      if (ringing == n['offer_id']) unawaited(stopRing());
      unawaited(showDeviceNotice(n));
      unawaited(backend.refresh());
    } else {
      unawaited(showDeviceNotice(n, ring: n['kind'] != 'offer' || !foreground));
      if (n['kind'] == 'offer') {
        unawaited(backend.refresh());
        startRing('${n['offer_id']}', DateTime.tryParse('${n['expires_at']}'));
      }
    }
    unawaited(load());
  }

  void setForeground(bool value) {
    foreground = value;
    if (!value) {
      unawaited(stopRing());
    } else {
      unawaited(load());
      syncOffers();
      if (!deviceRegistered &&
          (lastDeviceAttempt == null ||
              DateTime.now().difference(lastDeviceAttempt!).inSeconds >= 30)) {
        unawaited(enableDeviceNotifications(requestPermission: false));
      }
    }
  }

  void syncOffers() {
    if (closed) return;
    final offers = backend.requests
        .where((r) => backend.offerSeconds(r) > 0)
        .toList();
    if (ringing != null &&
        (!backend.tracking ||
            backend.activeRide != null ||
            !offers.any((r) => r['offer_id'] == ringing))) {
      final id = ringing!;
      unawaited(stopRing());
      unawaited(cancelDeviceOffer(id));
    }
    if (foreground &&
        backend.tracking &&
        backend.subscribed &&
        offers.isNotEmpty) {
      final r = offers.first;
      startRing(
        '${r['offer_id']}',
        DateTime.now().add(Duration(seconds: backend.offerSeconds(r))),
      );
    }
  }

  void startRing(String id, DateTime? expires) {
    if (!foreground ||
        !backend.captain ||
        !backend.tracking ||
        !backend.subscribed ||
        rung.contains(id) ||
        noticeExpired({'expires_at': expires?.toIso8601String()}))
      return;
    rung.add(id);
    ringTimer?.cancel();
    ringing = id;
    audioQueue = audioQueue.catchError((_) {}).then((_) async {
      await player.stop();
      if (ringing != id || closed) return;
      await player.setReleaseMode(ReleaseMode.loop);
      if (offerRingDuration(expires) == Duration.zero) {
        if (ringing == id) ringing = null;
        return;
      }
      await player.play(AssetSource('audio/captain_request.mp3'));
      if (ringing != id || closed) {
        await player.stop();
        return;
      }
      ringTimer = Timer(offerRingDuration(expires), () {
        if (ringing == id) {
          unawaited(stopRing());
          unawaited(cancelDeviceOffer(id));
        }
      });
    });
  }

  Future<void> stopRing() {
    ringing = null;
    ringTimer?.cancel();
    ringTimer = null;
    audioQueue = audioQueue.catchError((_) {}).then((_) => player.stop());
    return audioQueue;
  }

  Future<void> cancelDeviceOffer(String id) async {
    try {
      await cancelAppleOffer(id);
      if (!nativeReady) return;
      await nativeNotices.cancel(noticeId(id));
    } catch (error) {
      deviceError = describeDeviceError(error);
    }
  }

  Future<void> silenceOffer(String id) async {
    rung.add(id);
    if (ringing == id) await stopRing();
    await cancelDeviceOffer(id);
  }

  void tap(Map<String, dynamic> raw) {
    final n = noticeData(raw);
    if (user == null) {
      pending = n;
      return;
    }
    if ((n['recipient_id'] ?? n['user_id']) != user) return;
    if (n['kind'] == 'offer' && noticeExpired(n)) {
      unawaited(load());
      return;
    }
    unawaited(read(n));
    open(n);
  }

  Future<void> read(Json n) async {
    final id = n['id'] ?? n['notification_id'];
    if (id == null) return;
    try {
      await rpc('read', {'id': id});
      await load();
    } catch (_) {}
  }

  Future<void> readAll() async {
    await rpc('read_all');
    await load();
  }

  @override
  void dispose() {
    closed = true;
    backend.removeListener(changed);
    backend.beforeSignOut = null;
    backend.enableOrderNotifications = null;
    backend.silenceOffer = null;
    poll?.cancel();
    ringTimer?.cancel();
    auth?.cancel();
    tokenRefresh?.cancel();
    foregroundMessages?.cancel();
    openedMessages?.cancel();
    if (channel != null) unawaited(backend.db.removeChannel(channel!));
    unawaited(stopRing().whenComplete(player.dispose));
    super.dispose();
  }
}
