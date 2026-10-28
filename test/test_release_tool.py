"""Release regression tests; GitHub and Git writes are mocked."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('sylphy_release', Path(__file__).resolve().parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'pubspec.yaml').write_text('name: sylphy_music\nversion: 0.2.0+2\n', encoding='utf-8')
        for name in ['version.json', 'version-beta.json']:
            (self.root / name).write_text('{"latest":null,"history":[]}', encoding='utf-8')
        self.root_patch = patch.object(release, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_dry_run_is_pure(self):
        before = (self.root / 'pubspec.yaml').read_bytes()
        with patch.object(release, 'prepare') as prepare, patch.object(release, 'publish') as publish, redirect_stdout(io.StringIO()):
            self.assertEqual(release.main(['--version', '0.3.0', '--build', '3', '--dry-run']), 0)
        prepare.assert_not_called()
        publish.assert_not_called()
        self.assertEqual((self.root / 'pubspec.yaml').read_bytes(), before)
        self.assertFalse((self.root / 'build').exists())

    def test_invalid_or_reused_build_number_is_rejected(self):
        for number in ['1', '2', '65536']:
            with self.assertRaises(ValueError), redirect_stdout(io.StringIO()):
                release.main(['--version', '0.3.0', '--build', number, '--dry-run'])

    def test_manifest_preserves_history_without_duplicates(self):
        old = {'version': '0.2.0', 'build': 2}
        new = {'version': '0.3.0', 'build': 3}
        value = release.manifest({'latest': old, 'history': [old]}, new)
        self.assertEqual(value, {'latest': new, 'history': [old]})
        self.assertEqual(release.manifest(value, new), value)

    def fixture(self, fail_upload=False):
        output = self.root / 'output'
        output.mkdir()
        artifacts = {key: key + '.bin' for key in [*release.ABIS.values(), 'windows', 'windows_portable']}
        for name in [*artifacts.values(), 'SHA256SUMS.txt']:
            (output / name).write_bytes(name.encode())
        record = {'version': '0.3.0-beta', 'build': 3, 'artifacts': artifacts,
                  'sha256': {name: release.digest(output / name) for name in [*artifacts.values(), 'SHA256SUMS.txt']}}
        latest = {'version': record['version'], 'build': 3, 'name': 'test', 'notes': 'test', 'page': 'https://github.com/ymltsh/SylphyMusic/releases/tag/test'}
        calls = []
        def api(method, path, token, body=None, upload=None):
            calls.append((method, path, body))
            if method == 'POST' and path.endswith('/releases'):
                return {'id': 9, 'upload_url': 'https://uploads.github.com/repos/ymltsh/SylphyMusic/releases/9/assets{?name,label}'}
            if upload and fail_upload:
                raise ValueError('simulated upload failure')
            return [] if method == 'GET' else {}
        return output, record, latest, calls, api

    def test_default_cli_publishes_and_skip_checks_is_allowed(self):
        output, record, latest, calls, api = self.fixture()
        with patch.object(release, 'prepare', return_value=record) as prepare, patch.object(release, 'publish') as publish, patch.object(release, 'scan_packages'), patch.object(release, 'run') as run, redirect_stdout(io.StringIO()):
            self.assertEqual(release.main(['--version', '0.3.0', '--build', '3', '--skip-checks']), 0)
        self.assertTrue(prepare.call_args.args[0].skip_checks)
        publish.assert_called_once()
        self.assertIn('version: 0.3.0+3', (self.root / 'pubspec.yaml').read_text())
        self.assertEqual(run.call_args.args[0][1], 'tool/verify_android_signing.py')

    def test_uploads_before_visibility_and_commits_only_channel_manifest(self):
        output, record, latest, calls, api = self.fixture()
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run') as run, patch.object(release, 'token_from_environment', return_value='synthetic-token'), redirect_stdout(io.StringIO()):
            release.publish(SimpleNamespace(no_push=False), record, output, 'v0.3.0-beta+3', latest)
        mutations = [(method, path, body) for method, path, body in calls if method != 'GET']
        self.assertTrue(mutations[0][2]['draft'])
        self.assertTrue(mutations[0][2]['prerelease'])
        self.assertEqual(mutations[-1][0], 'PATCH')
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands[0], ['git', 'add', '--', 'version-beta.json'])
        self.assertEqual(commands[1][-2:], ['--', 'version-beta.json'])
        self.assertIn('--only', commands[1])
        self.assertEqual(commands[2], ['git', 'push', 'origin', 'main'])
        self.assertIsNone(json.loads((self.root / 'version.json').read_text())['latest'])

    def test_upload_failure_leaves_manifest_and_git_untouched(self):
        output, record, latest, calls, api = self.fixture(True)
        before = (self.root / 'version-beta.json').read_bytes()
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run') as run, patch.object(release, 'token_from_environment', return_value='synthetic-token'), self.assertRaises(ValueError):
            release.publish(SimpleNamespace(no_push=False), record, output, 'v0.3.0-beta+3', latest)
        self.assertFalse(any(method == 'PATCH' for method, _, _ in calls))
        self.assertEqual((self.root / 'version-beta.json').read_bytes(), before)
        run.assert_not_called()

    def test_no_push_keeps_local_manifest_and_pending_acceptance_does_not_block(self):
        output, record, latest, calls, api = self.fixture()
        record['version'] = latest['version'] = '1.0.0'
        (self.root / 'docs').mkdir()
        (self.root / 'docs/RELEASE_GATES.md').write_text('- [ ] Pending acceptance\n')
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run') as run, patch.object(release, 'token_from_environment', return_value='synthetic-token'), redirect_stdout(io.StringIO()):
            release.publish(SimpleNamespace(no_push=True), record, output, 'v1.0.0+3', latest)
        self.assertFalse(next(body for method, path, body in calls if method == 'POST' and path.endswith('/releases'))['prerelease'])
        self.assertEqual(json.loads((self.root / 'version.json').read_text())['latest'], latest)
        run.assert_not_called()

    def test_reuse_needs_artifacts_but_no_source_fingerprint_or_record(self):
        output = self.root / 'reuse'
        output.mkdir()
        names = [f'sylphy-music-1.0.0-12-{abi}.apk' for abi in release.ABIS]
        names += ['sylphy-music-setup-1.0.0-12.exe', 'sylphy-music-windows-1.0.0-12.zip']
        for name in names:
            (output / name).write_bytes(b'fixture')
        record = release.existing_packages(output, '1.0.0', 12)
        self.assertEqual(len(record['sha256']), 6)
        self.assertFalse((output / 'release-record.json').exists())
        (output / names[0]).unlink()
        with self.assertRaises(ValueError):
            release.existing_packages(output, '1.0.0', 12)

    def test_private_data_scan_does_not_print_secrets(self):
        output = self.root / 'packages'
        output.mkdir()
        credentials = self.root / 'synthetic-credentials.txt'
        credentials.write_text('https://example.invalid\nsynthetic-user\nsynthetic-secret\n')
        with zipfile.ZipFile(output / 'test.apk', 'w', zipfile.ZIP_DEFLATED) as apk:
            apk.writestr('assets/test', b'synthetic-secret')
        with self.assertRaises(ValueError) as error:
            release.scan_packages(output, {'artifacts': {'android_arm64': 'test.apk'}}, [str(credentials)])
        self.assertNotIn('synthetic-secret', str(error.exception))


if __name__ == '__main__':
    unittest.main()
