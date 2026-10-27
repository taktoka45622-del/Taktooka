import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:taktooka/core/design.dart';
import 'package:taktooka/core/ride_emergency.dart';
import 'package:taktooka/core/gender_copy.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/map_handoff.dart';
import 'package:taktooka/widgets/profile_photo.dart';
import 'package:taktooka/widgets/ride_places.dart';
import 'package:taktooka/widgets/round_trip_summary.dart';
import 'package:taktooka/widgets/ride_search_images.dart';

class ActiveRideCard extends StatelessWidget {
  final Json ride;
  final Json? contact;
  final bool captain, busy, showCancellation;
  final DateTime now;
  final VoidCallback? onEmergency;
  final bool emergencyBusy;
  final void Function(bool pickup)? onPlace;
  final void Function(String) onStatus, onContact;
  const ActiveRideCard({
    super.key,
    required this.ride,
    required this.contact,
    required this.captain,
    required this.busy,
    required this.now,
    required this.onStatus,
    required this.onContact,
    this.showCancellation = true,
    this.onEmergency,
    this.emergencyBusy = false,
    this.onPlace,
  });

  @override
  Widget build(BuildContext context) {
    final state = ride['status'];
    final roundTrip = ride['round_trip'] == true;
    final stage = ride['round_trip_stage'];
    final wallet = ride['payment_method'] == 'wallet';
    final locationAt = DateTime.tryParse('${contact?['location_at']}');
    final stale =
        locationAt == null || now.difference(locationAt).inSeconds >= 15;
    final label = switch (state) {
      'pending' => 'جاري البحث عن كابتن قريب',
      'accepted' => 'الكابتن بالطريق',
      'arrived' => 'الكابتن وصل',
      'in_progress' =>
        roundTrip && stage == 'waiting'
            ? 'بانتظار الرجعة'
            : roundTrip && stage == 'returning'
            ? 'الرجعة جارية'
            : 'الرحلة جارية',
      'completed' => 'الرحلة مكتملة',
      _ => 'الرحلة ملغاة',
    };
    final green = state == 'arrived' || state == 'in_progress';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: themedSurface(context, pink),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                wallet ? Icons.account_balance_wallet : Icons.payments_outlined,
                color: scarlet,
                size: 25,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: AppText(
                  ride['coupon_reward_type'] == 'free_ride'
                      ? 'رحلة مجانية — بدون دفع كروة'
                      : wallet ? 'الرحلة مدفوعة بالمحفظة' : 'الدفع كاش عند الوصول',
                  style: heading(15).copyWith(color: scarlet),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: green
                      ? const Color(0xffeff9f1)
                      : const Color(0xfff4f5f7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      state == 'arrived' ? Icons.directions_car : Icons.circle,
                      size: state == 'arrived' ? 24 : 10,
                      color: green ? const Color(0xff198936) : muted,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: AppText(
                        label,
                        style: heading(15).copyWith(
                          color: green ? const Color(0xff198936) : muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PaperCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                radius: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const AppText(
                      'الكروة',
                      style: TextStyle(color: muted, fontSize: 14),
                    ),
                    AppText(
                      money(
                        captain && ride['coupon_reward_type'] != 'free_ride'
                            ? ride['fare']
                            : ride['customer_due'] ?? ride['fare'],
                      ),
                      style: heading(23),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        RoundTripSummary(ride: ride, now: now),
        RidePlaces(ride: ride, onPlace: onPlace),
        if (captain && (ride['discount'] as num? ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AppText(
              ride['coupon_reward_type'] == 'free_ride'
                  ? 'رحلة مجانية للزبون؛ تحصل على يوم اشتراك إضافي بعد إكمالها'
                  : 'خصم الزبون ${money(ride['discount'])}؛ تستحق الكروة كاملة',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        if (state == 'pending') ...[
          const SizedBox(height: 12),
          const RideSearchImages(
            assets: [
              'assets/ride_search/1.png',
              'assets/ride_search/2.png',
              'assets/ride_search/3.png',
              'assets/ride_search/4.png',
              'assets/ride_search/5.png',
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          PaperCard(
            radius: 12,
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Row(
                  children: [
                    ProfilePhoto(path: contact?['avatar_path'], size: 50),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            captain ? 'الزبون' : 'الكابتن',
                            style: const TextStyle(color: muted, fontSize: 14),
                          ),
                          AppText(
                            '${contact?['name'] ?? 'جارٍ تحميل معلومات التواصل'}',
                            style: heading(17),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!captain &&
                    ['accepted', 'arrived', 'in_progress'].contains(state)) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: stale
                          ? const Color(0xfffff5da)
                          : const Color(0xffeff9f1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          stale ? Icons.schedule : Icons.location_on_outlined,
                          size: 19,
                          color: stale
                              ? const Color(0xffaf7413)
                              : const Color(0xff198936),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: AppText(
                            locationAt == null
                                ? 'بانتظار موقع الكابتن الفعلي'
                                : stale
                                ? 'اتصال موقع الكابتن متأخر؛ المتابعة متوقفة مؤقتًا'
                                : 'متابعة موقع الكابتن مباشرة',
                            style: TextStyle(
                              fontSize: 12,
                              color: stale
                                  ? const Color(0xffaf7413)
                                  : const Color(0xff198936),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (state == 'accepted' && ride['captain_eta_s'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AppText(
                'الوصول خلال حوالي ${((ride['captain_eta_s'] as num) / 60).ceil()} دقيقة',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
            ),
          const SizedBox(height: 8),
          if (rideEmergencyReady(ride, now))
            FilledButton(
              onPressed: emergencyBusy ? null : onEmergency,
              style: FilledButton.styleFrom(
                backgroundColor: scarlet,
                foregroundColor: Colors.white,
                disabledBackgroundColor: scarlet.withValues(alpha: 0.8),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 84),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Center(
                      child: emergencyBusy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.health_and_safety_outlined,
                              size: 27,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText(
                          emergencyBusy ? 'جاري الإرسال…' : 'حالة طارئة',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AppText(
                          emergencyBusy
                              ? 'نرسل البلاغ للدعم'
                              : 'اضغط إن حدث شيء',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.28),
                      ),
                    ),
                    child: const Directionality(
                      textDirection: TextDirection.ltr,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText(
                            'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          AppText(
                            '911',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (['accepted', 'arrived'].contains(state))
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: contact == null ? null : () => onContact('tel'),
                    icon: const Icon(Icons.call, color: scarlet),
                    label: const AppText('اتصال', style: TextStyle(color: ink)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xffaaaaaa)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: contact == null ? null : () => onContact('wa'),
                    icon: const Icon(
                      Icons.phone_in_talk_outlined,
                      color: Color(0xff19af5c),
                    ),
                    label: const AppText(
                      'واتساب',
                      style: TextStyle(color: ink),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xffaaaaaa)),
                    ),
                  ),
                ),
              ],
            ),
        ],
        if (captain &&
            ['accepted', 'arrived', 'in_progress'].contains(state)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final uri = rideWazeUri(ride);
              if (uri == null) return;
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (!await launchUrl(
                  uri,
                  mode: LaunchMode.externalApplication,
                )) {
                  messenger.showSnackBar(
                    const SnackBar(content: AppText('تعذّر فتح ويز')),
                  );
                }
              } catch (_) {
                messenger.showSnackBar(
                  const SnackBar(content: AppText('تعذّر فتح ويز')),
                );
              }
            },
            icon: const Icon(Icons.navigation_outlined),
            label: AppText(
              state == 'in_progress'
                  ? stage == 'returning'
                        ? 'ويز للرجعة'
                        : 'ويز للوجهة'
                  : 'ويز للزبون',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy
                ? null
                : () => onStatus(
                    state == 'accepted'
                        ? 'arrived'
                        : state == 'arrived'
                        ? 'in_progress'
                        : roundTrip && stage == 'outbound'
                        ? 'round_trip_wait'
                        : roundTrip && stage == 'waiting'
                        ? 'round_trip_return'
                        : 'completed',
                  ),
            child: AppText(
              state == 'accepted'
                  ? 'وصلت لمكان الزبون'
                  : state == 'arrived'
                  ? 'بدء الرحلة'
                  : roundTrip && stage == 'outbound'
                  ? 'وصلت للوجهة · بدء الانتظار'
                  : roundTrip && stage == 'waiting'
                  ? 'بدء الرجعة'
                  : 'إنهاء الرحلة',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
        if (showCancellation &&
            ['pending', 'accepted', 'arrived'].contains(state))
          TextButton(
            onPressed: busy ? null : () => onStatus('cancelled'),
            child: const AppText(
              'إلغاء الرحلة',
              style: TextStyle(color: scarlet, fontSize: 16),
            ),
          ),
      ],
    );
  }
}
