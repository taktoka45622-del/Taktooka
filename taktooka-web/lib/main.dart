import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/app.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/map_config.dart';
import 'package:taktooka/services/backend.dart';
import 'package:taktooka/services/booking_pricing.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appPreferences.load();
  await BookingPricing.restore();
  await appPreferences.prepareAccountEntry();
  await Supabase.initialize(url: supabaseUrl, anonKey: publishableKey);
  try {
    await ensureMapConfiguration().timeout(const Duration(seconds: 5));
  } catch (_) {}
  runApp(const TaktookaApp());
}
