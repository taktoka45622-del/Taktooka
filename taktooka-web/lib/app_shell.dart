import 'package:taktooka/core/display_format.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/app_translations.dart';
import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/feature_navigation.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/core/ride_format.dart';
import 'package:taktooka/models/address_choice.dart';
import 'package:taktooka/pages/about_page.dart';
import 'package:taktooka/pages/account_page.dart';
import 'package:taktooka/pages/address_search_page.dart';
import 'package:taktooka/pages/captain_registration_page.dart';
import 'package:taktooka/pages/chat_page.dart';
import 'package:taktooka/pages/city_page.dart';
import 'package:taktooka/pages/history_page.dart';
import 'package:taktooka/pages/home_page.dart';
import 'package:taktooka/pages/lines_page.dart';
import 'package:taktooka/pages/notifications_page.dart';
import 'package:taktooka/pages/offers_page.dart';
import 'package:taktooka/pages/phone_login_page.dart';
import 'package:taktooka/pages/profile_page.dart';
import 'package:taktooka/pages/ride_map_page.dart';
import 'package:taktooka/pages/settings_page.dart';
import 'package:taktooka/pages/wallet_page.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/invite_friends.dart';
import 'package:taktooka/services/location_disclosure.dart';
import 'package:taktooka/services/map_handoff.dart';
import 'package:taktooka/services/notifications.dart';
import 'package:taktooka/widgets/brand_title.dart';
import 'package:taktooka/widgets/street_map_layer.dart';
import 'package:taktooka/widgets/tuktuk_loader.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  final backend = Backend();
  static const mapChannel = MethodChannel('taktooka/map_handoff');
  String? _sharedLocation;
  bool _openingSharedLocation = false;
  Future<void> initializeMapHandoff() async {
    mapChannel.setMethodCallHandler((call) async {
      if (call.method == 'location' && call.arguments is String) {
        _sharedLocation = call.arguments as String;
        unawaited(openSharedLocation());
      }
    });
    try {
      _sharedLocation = await mapChannel.invokeMethod<String>(
        'initialLocation',
      );
      unawaited(openSharedLocation());
    } on MissingPluginException {}
  }

  Future<void> openSharedLocation() async {
    if (!mounted ||
        _sharedLocation == null ||
        !backend.loggedIn ||
        backend.profile == null ||
        _openingSharedLocation)
      return;
    final text = _sharedLocation!;
    _sharedLocation = null;
    _openingSharedLocation = true;
    try {
      if (backend.captain || backend.activeRide != null) {
        toast('فتح الموقع للحجز متاح للزبون بدون رحلة جارية');
        return;
      }
      final destination = await resolveSharedLocation(text);
      if (!mounted) return;
      if (destination == null) {
        toast('تعذّر قراءة الموقع؛ شارك رابط الموقع من واتساب أو الخرائط');
        return;
      }
      book(
        favoriteDestination: AddressChoice('الموقع المرسل إليك', destination),
      );
    } catch (_) {
      toast('تعذّر فتح الموقع المرسل، أعد المحاولة');
    } finally {
      _openingSharedLocation = false;
      if (_sharedLocation != null) unawaited(openSharedLocation());
    }
  }

  int tab = 0;
  final _tabBodies = List<Widget?>.filled(4, null);
  int _renderedTab = -1;
  bool busy = false;
  late final notices = NotificationCenter(backend, openNotice);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(StreetMapLayer.warmUp());
    unawaited(initializeMapHandoff());
    backend.addListener(changed);
    notices.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(startWithPermissions());
    });
  }

  Future<void> startWithPermissions() async {
    var locationAllowed = false;
    try {
      final permission = await requestLocationAccess();
      locationAllowed =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (error) {
      debugPrint('Taktooka location permission unavailable');
    }
    if (!mounted) return;
    if (locationAllowed)
      unawaited(backend.locate().then<void>((_) {}, onError: (Object _) {}));
    unawaited(backend.start());
    await notices.requestStartupPermission();
    if (!mounted) return;
    unawaited(notices.start());
  }

  void changed() {
    if (mounted) setState(() {});
    if (_sharedLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(openSharedLocation()),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    backend.setForeground(state == AppLifecycleState.resumed);
    notices.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mapChannel.setMethodCallHandler(null);
    notices.removeListener(changed);
    notices.dispose();
    backend.removeListener(changed);
    backend.dispose();
    super.dispose();
  }

  void toast(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: AppText(text, textDirection: TextDirection.rtl),
        action: SnackBarAction(
          label: 'إغلاق',
          onPressed: () => messenger.hideCurrentSnackBar(),
        ),
      ),
    );
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      toast(readable(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openLines([String? id]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LinesPage(b: backend, initialId: id),
      ),
    );
  }

  void openNotice(Json n) {
    if (!mounted || !backend.loggedIn) return;
    if (n['kind'] == 'offer') {
      Navigator.of(context).popUntil((route) => route.isFirst);
      unawaited(openNotifiedRide(n));
      return;
    }
    final navigator = Navigator.of(context);
    navigator.popUntil((route) => route.isFirst);
    switch (n['screen']) {
      case 'lines':
        openLines(n['line_id'] as String?);
        break;
      case 'support':
        support();
        break;
      case 'offers':
        setState(() => tab = 2);
        break;
      case 'wallet':
        wallet();
        break;
      case 'application':
        applyCaptain();
        break;
      case 'account':
        editAccount();
        break;
      case 'ride':
        unawaited(openNotifiedRide(n));
        break;
      default:
        setState(() => tab = 0);
    }
  }

  Future<void> openNotifiedRide(Json n) async {
    try {
      await backend.refresh();
      if (backend.captain) await backend.restoreTracking();
      await backend.refresh(lightweight: true);
      if (!mounted) return;
      final id = n['ride_id'];
      if (backend.activeRide?['id'] == id ||
          backend.requests.any((r) => r['id'] == id)) {
        setState(() => tab = 0);
        book();
        return;
      }
      final matches = backend.rides.where((r) => r['id'] == id).toList();
      if (matches.isEmpty) {
        toast('هذا الطلب لم يعد متاحًا');
        return;
      }
      final r = matches.first;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const AppText('تفاصيل المشوار')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppText(
                    labels[r['status']] ?? 'المشوار',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  AppText('رقم المشوار: ${r['id']}'),
                  AppText('الكروة: ${amount(r['fare'])}'),
                  AppText(
                    '${r['pickup_name'] ?? ''} ← ${r['destination_name'] ?? ''}',
                  ),
                  AppText(displayDateTime(r['created_at'])),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      toast(readable(e));
    }
  }

  void account() {
    setState(() => tab = 3);
  }

  void editAccount() => openFeature(
    context,
    backend,
    'حسابي',
    () => AccountPage(backend: backend, busy: busy, run: run, toast: toast),
  );
  bool requireLogin() {
    if (!backend.loggedIn) {
      editAccount();
      return false;
    }
    return true;
  }

  void book({AddressChoice? favoriteDestination}) {
    openFeature(
      context,
      backend,
      'مشوار',
      () => RideMap(
        backend: backend,
        busy: busy,
        run: run,
        toast: toast,
        openAccount: editAccount,
        favoriteDestination: favoriteDestination,
      ),
    );
  }

  void support() {
    if (requireLogin())
      openFeature(context, backend, 'الدعم', () => ChatPage(b: backend));
  }

  void wallet() {
    if (requireLogin())
      openFeature(
        context,
        backend,
        'المحفظة',
        () => WalletPage(b: backend, support: support),
      );
  }

  Future<void> addresses() async {
    if (!requireLogin()) return;
    final choice = await Navigator.of(context).push<AddressChoice>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const BrandTitle(), centerTitle: true),
          body: AddressSearch(
            b: backend,
            title: 'العناوين المفضلة',
            savedOnly: true,
          ),
        ),
      ),
    );
    if (choice != null && mounted) {
      book(favoriteDestination: choice);
    }
  }

  Future<void> selectCity() async {
    await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const BrandTitle(), centerTitle: true),
          body: CityPage(b: backend),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void applyCaptain() {
    if (!requireLogin()) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaptainRegistrationPage(backend: backend),
      ),
    );
  }

  void settings() => openFeature(
    context,
    backend,
    'الإعدادات',
    () => SettingsPage(
      backend: backend,
      editAccount: editAccount,
      selectCity: selectCity,
      run: run,
    ),
  );

  void about() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const BrandTitle(), centerTitle: true),
        body: AboutPage(support: support),
      ),
    ),
  );

  Widget tabBody(int index) {
    return switch (index) {
      0 => HomePage(
        b: backend,
        book: book,
        lines: openLines,
        history: () => setState(() => tab = 1),
        offers: () => setState(() => tab = 2),
        apply: applyCaptain,
        city: selectCity,
        support: support,
      ),
      1 => HistoryPage(backend: backend, active: tab == 1),
      2 => OffersPage(b: backend, run: run, login: editAccount),
      _ => ProfileHub(
        b: backend,
        edit: editAccount,
        wallet: wallet,
        history: () => setState(() => tab = 1),
        addresses: addresses,
        offers: () => setState(() => tab = 2),
        support: support,
        settings: settings,
        about: about,
        invite: () => inviteFriends(context),
      ),
    };
  }

  List<Widget> tabViews() {
    final switched = _renderedTab != tab;
    for (var i = 0; i < 4; i++) {
      if (i == tab || (switched && i == 1 && _tabBodies[i] != null))
        _tabBodies[i] = tabBody(i);
    }
    _renderedTab = tab;
    return List.generate(
      4,
      (i) => TickerMode(
        enabled: i == tab,
        child: RepaintBoundary(child: _tabBodies[i] ?? const SizedBox.shrink()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PreferencesScope.of(context);
    if (!backend.loggedIn) {
      _tabBodies.fillRange(0, 4, null);
      _renderedTab = -1;
      return Scaffold(
        appBar: AppBar(centerTitle: true, title: const BrandTitle()),
        body: PhoneLoginPage(backend: backend),
      );
    }
    if (tab > 3) tab = 3;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const BrandTitle(),
        toolbarHeight: 72,
        leadingWidth: 90,
        leading: tab == 0 && !backend.captain
            ? TextButton.icon(
                onPressed: selectCity,
                icon: const Icon(Icons.location_on, size: 22),
                label: AppText(
                  backend.city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NotificationsPage(center: notices),
              ),
            ),
            icon: Badge(
              isLabelVisible: notices.unread > 0,
              label: AppText('${notices.unread}'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          IconButton(
            onPressed: support,
            icon: const Icon(Icons.headset_mic_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const TuktukLoader(),
          if (backend.error != null)
            Material(
              color: themedSurface(context, const Color(0xfffff2d6)),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        backend.error!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      onPressed: () => backend.refresh(),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(index: tab, children: tabViews()),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 78,
        selectedIndex: tab,
        onDestinationSelected: (i) {
          if (i != tab) setState(() => tab = i);
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: const Color(0xffffe7e7),
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: red),
            label: uiText('الرئيسية'),
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history, color: red),
            label: uiText('الرحلات'),
          ),
          NavigationDestination(
            icon: Icon(Icons.local_offer_outlined),
            selectedIcon: Icon(Icons.local_offer, color: red),
            label: uiText('العروض'),
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: red),
            label: uiText('حسابي'),
          ),
        ],
      ),
    );
  }
}
