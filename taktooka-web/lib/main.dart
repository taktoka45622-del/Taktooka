import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:taktooka/app.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/services/backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: publishableKey);
  await appPreferences.load();
  runApp(const TaktookaApp());
}
