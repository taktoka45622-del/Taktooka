import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taktooka/core/app_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'first install shows onboarding; normal reopening skips; logout restores it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPreferences();
      await prefs.load();
      expect(prefs.onboardingSeen, false);
      await prefs.completeOnboarding();
      final reopened = AppPreferences();
      await reopened.load();
      expect(reopened.onboardingSeen, true);
      await reopened.showOnboardingAfterLogout();
      final afterLogout = AppPreferences();
      await afterLogout.load();
      expect(afterLogout.onboardingSeen, false);
      await afterLogout.completeOnboarding();
      await afterLogout.load();
      expect(afterLogout.onboardingSeen, true);
    },
  );
  test(
    'existing accounts skip upgrade onboarding until explicit logout',
    () async {
      SharedPreferences.setMockInitialValues({'has_used_account_v1': true});
      final prefs = AppPreferences();
      await prefs.load();
      expect(prefs.onboardingSeen, true);
      await prefs.showOnboardingAfterLogout();
      await prefs.load();
      expect(prefs.onboardingSeen, false);
    },
  );
}
