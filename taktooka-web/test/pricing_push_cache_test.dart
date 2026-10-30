import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/local_fare.dart';
import 'package:taktooka/services/booking_pricing.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BookingPricing.settings = Map.of(LocalFare.defaults);
  });
  Map<String, dynamic> update(int rev) => {
    'kind': 'pricing_update',
    'pricing_json': jsonEncode({
      ...LocalFare.defaults,
      'revision': rev,
      'night_amount': rev * 10,
    }),
  };
  test(
    'background payload is persisted and restored without a server request',
    () async {
      expect(await BookingPricing.applyPayload(update(12)), true);
      BookingPricing.settings = Map.of(LocalFare.defaults);
      await BookingPricing.restore();
      expect(BookingPricing.settings['revision'], 12);
      expect(BookingPricing.settings['night_amount'], 120);
    },
  );
  test(
    'out-of-order pushes cannot overwrite a newer stored revision',
    () async {
      await BookingPricing.applyPayload(update(15));
      await BookingPricing.applyPayload(update(12));
      BookingPricing.settings = Map.of(LocalFare.defaults);
      await BookingPricing.restore();
      expect(BookingPricing.settings['revision'], 15);
    },
  );
  test(
    'duplicate updates are idempotent and malformed data is ignored',
    () async {
      await BookingPricing.applyPayload(update(14));
      await BookingPricing.applyPayload(update(14));
      await BookingPricing.applyPayload({
        'kind': 'pricing_update',
        'pricing_json': 'broken',
      });
      expect(BookingPricing.settings['revision'], 14);
      expect(await BookingPricing.applyPayload({'kind': 'offer'}), false);
    },
  );
  test(
    'a background update avoids an extra configuration fetch on opening',
    () async {
      await BookingPricing.applyPayload(update(20));
      var requests = 0;
      await BookingPricing.syncOnce(() async {
        requests++;
        return LocalFare.defaults;
      });
      expect(requests, 0);
      expect(BookingPricing.settings['revision'], 20);
    },
  );
}
