import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

class AndroidReleaseSigningTest(unittest.TestCase):
    def test_missing_signing_blocks_before_flutter_and_preserves_existing_keystore(self):
        source = Path(__file__).resolve().parents[2] / 'scripts/package-android-apk.sh'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'scripts').mkdir()
            (root / 'android').mkdir()
            (root / 'bin').mkdir()
            shutil.copy(source, root / 'scripts/package-android-apk.sh')
            keystore = root / 'android/upload-keystore.jks'
            keystore.write_text('user-owned')
            marker = root / 'flutter-called'
            fake = root / 'bin/flutter'
            fake.write_text(f'#!/bin/sh\ntouch "{marker}"\nexit 0\n')
            fake.chmod(0o700)
            env = {key: value for key, value in os.environ.items() if not key.startswith('ANDROID_KEY')}
            env['PATH'] = str(root / 'bin') + os.pathsep + env['PATH']
            result = subprocess.run(['bash', str(root / 'scripts/package-android-apk.sh')], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(marker.exists(), 'Unsigned release must not reach Flutter')
            self.assertEqual(keystore.read_text(), 'user-owned')
            self.assertIn('signing', result.stderr.lower())

if __name__ == '__main__': unittest.main()
