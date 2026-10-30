import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/app_preferences.dart';
import 'package:taktooka/core/backend_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('fresh device opens registration', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = AppPreferences();
    await preferences.load();
    await preferences.prepareAccountEntry();
    expect(preferences.hasUsedAccount, isFalse);
  });
  test('account use survives a new preferences instance', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = AppPreferences();
    await preferences.rememberAccountUse();
    final restored = AppPreferences();
    await restored.load();
    await restored.prepareAccountEntry();
    expect(restored.hasUsedAccount, isTrue);
  });
  test(
    'saved session survives startup while previous device use is remembered',
    () async {
      final key =
          'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';
      SharedPreferences.setMockInitialValues({key: 'old-session'});
      final preferences = AppPreferences();
      await preferences.load();
      await preferences.prepareAccountEntry();
      expect(preferences.hasUsedAccount, isTrue);
      expect((await SharedPreferences.getInstance()).getString(key), 'old-session');
    },
  );
}
