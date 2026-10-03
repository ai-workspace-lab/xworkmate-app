"""Exercise the macOS Bash 3.2 CI path without signing or endpoint overrides."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class IosUnsignedCiTest(unittest.TestCase):
    def test_unsigned_build_handles_empty_and_multiple_optional_endpoints(self):
        for endpoints in ({}, {'XWORKMATE_ACCOUNT_BASE_URL': 'https://accounts.example',
                               'XWORKMATE_MANAGED_BRIDGE_URL': 'https://bridge.example'}):
            with self.subTest(endpoints=bool(endpoints)), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'scripts/ci').mkdir(parents=True)
                (root / 'bin').mkdir()
                for name in ('build_matrix_artifacts.sh', 'build_version.py'):
                    shutil.copy(ROOT / 'scripts/ci' / name, root / 'scripts/ci' / name)
                (root / 'pubspec.yaml').write_text('version: 1.0.0-beta.1+2\n')
                fake = root / 'bin/flutter'
                fake.write_text('#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\n'
                                'if sys.argv[1] == "build":\n'
                                ' Path("flutter-args.json").write_text(json.dumps(sys.argv[1:]))\n'
                                ' p=Path("build/ios/iphoneos/Runner.app");p.mkdir(parents=True)\n'
                                ' (p/"fixture").write_text("unsigned-test")\n')
                fake.chmod(0o700)
                env = {'PATH': str(root / 'bin') + os.pathsep + os.environ['PATH'], **endpoints}
                result = subprocess.run(['/bin/bash', str(root / 'scripts/ci/build_matrix_artifacts.sh'),
                                         'ios', 'arm64', 'ipa', 'false'], env=env,
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                args = json.loads((root / 'flutter-args.json').read_text())
                self.assertIn('--no-codesign', args)
                self.assertTrue((root / 'dist/ios/XWorkmate.app.zip').is_file())
                for key, value in endpoints.items():
                    self.assertIn('--dart-define=' + key + '=' + value, args)
                self.assertEqual(sum(arg.startswith('--dart-define=XWORKMATE_ACCOUNT_BASE_URL=') for arg in args), int(bool(endpoints)))

if __name__ == '__main__':
    unittest.main()
