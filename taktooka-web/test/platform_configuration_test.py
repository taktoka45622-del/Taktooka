from pathlib import Path
import plistlib
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class PlatformConfigurationTest(unittest.TestCase):
    def plist(self, relative):
        return plistlib.loads((ROOT / relative).read_bytes())

    def test_ios_permissions_and_navigation(self):
        info = self.plist('ios/Runner/Info.plist')
        for key in ['NSLocationWhenInUseUsageDescription',
                    'NSLocationAlwaysAndWhenInUseUsageDescription',
                    'NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription']:
            self.assertTrue(info[key].strip())
        self.assertIn('location', info['UIBackgroundModes'])
        self.assertIn('remote-notification', info['UIBackgroundModes'])
        self.assertIn('waze', info['LSApplicationQueriesSchemes'])

    def test_shared_location_groups_match(self):
        runner = self.plist('ios/Runner/Runner.entitlements')
        share = self.plist('ios/ShareLocation/ShareLocation.entitlements')
        key = 'com.apple.security.application-groups'
        self.assertEqual(runner[key], share[key])
        self.assertIn('group.com.taktooka.taktooka', runner[key])

    def test_share_extension_inherits_flutter_version_for_all_builds(self):
        project = (ROOT / 'ios/Runner.xcodeproj/project.pbxproj').read_text()
        configs = re.findall(r'\w+ /\* (Debug|Release|Profile) \*/ = \{\s*isa = XCBuildConfiguration;(.*?)\n\t\t\};', project, re.S)
        share = [(name, block) for name, block in configs if 'INFOPLIST_FILE = ShareLocation/Info.plist;' in block]
        self.assertEqual({name for name, _ in share}, {'Debug', 'Release', 'Profile'})
        for name, block in share:
            self.assertIn('baseConfigurationReference = ', block)
            self.assertIn('CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";', block)
            self.assertIn('MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";', block)

    def test_ios_configuration_files_parse(self):
        for path in (ROOT / 'ios').rglob('*.plist'):
            if 'ephemeral' not in path.parts:
                plistlib.loads(path.read_bytes())
        for path in (ROOT / 'ios').rglob('*.entitlements'):
            plistlib.loads(path.read_bytes())

    def test_android_manifest_has_location_and_external_navigation(self):
        root = ET.parse(ROOT / 'android/app/src/main/AndroidManifest.xml').getroot()
        name = '{http://schemas.android.com/apk/res/android}name'
        permissions = {e.attrib[name] for e in root.findall('uses-permission')}
        self.assertIn('android.permission.ACCESS_FINE_LOCATION', permissions)
        self.assertIn('android.permission.FOREGROUND_SERVICE_LOCATION', permissions)
        schemes = {e.attrib.get('{http://schemas.android.com/apk/res/android}scheme') for e in root.findall('.//data')}
        self.assertIn('https', schemes)


if __name__ == '__main__':
    unittest.main()
