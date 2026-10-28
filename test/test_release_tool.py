"""Release-tool regression tests. All GitHub calls are mocked; no real releases or pushes."""
import base64
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('sylphy_release', Path(__file__).resolve().parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'pubspec.yaml').write_text('name: sylphy_music\nversion: 0.2.0+2\n', encoding='utf-8')
        self.patch = patch.object(release, 'ROOT', self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def test_dry_run_is_pure_and_uses_explicit_build(self):
        before = (self.root / 'pubspec.yaml').read_bytes()
        with patch.object(release, 'prepare') as prepare, patch.object(release, 'publish') as publish, redirect_stdout(io.StringIO()):
            self.assertEqual(release.main(['--version', '0.3.0', '--build', '3', '--beta2', '--dry-run']), 0)
        prepare.assert_not_called()
        publish.assert_not_called()
        self.assertEqual((self.root / 'pubspec.yaml').read_bytes(), before)
        self.assertFalse((self.root / 'build').exists())

    def test_build_number_cannot_go_backwards_or_be_reused_for_other_version(self):
        for args in [['--version', '0.3.0', '--build', '1'], ['--version', '0.3.0', '--build', '2'], ['--version', '0.3.0', '--build', '65536']]:
            with self.assertRaises(ValueError), redirect_stdout(io.StringIO()):
                release.main(args + ['--dry-run'])

    def test_manifest_history_is_preserved_and_deduplicated(self):
        old = {'version': '0.2.0', 'build': 2, 'notes': 'old'}
        new = {'version': '0.3.0', 'build': 3}
        value = release.manifest({'latest': old, 'history': [old]}, new)
        self.assertEqual(value, {'latest': new, 'history': [old]})
        self.assertEqual(release.manifest(value, new), value)

    def record(self):
        output = self.root / 'output'
        output.mkdir()
        artifacts = {key: key + '.bin' for key in [*release.ABIS.values(), 'windows', 'windows_portable']}
        for name in [*artifacts.values(), 'SHA256SUMS.txt']:
            (output / name).write_bytes(name.encode())
        record = {'version': '0.3.0-beta', 'build': 3, 'source_sha256': 'source', 'checks_passed': True,
                  'artifacts': artifacts, 'sha256': {n: release.digest(output / n) for n in [*artifacts.values(), 'SHA256SUMS.txt']}}
        (output / 'release-record.json').write_text(json.dumps(record), encoding='utf-8')
        return output, record

    def test_reuse_rejects_changed_sources_corrupt_assets_and_wrong_version(self):
        output, record = self.record()
        with patch.object(release, 'source_digest', return_value='source'):
            self.assertEqual(release.verify_record(output, record['version'], 3), record)
            with self.assertRaises(ValueError):
                release.verify_record(output, record['version'], 4)
            (output / record['artifacts']['windows']).write_bytes(b'corrupt')
            with self.assertRaises(ValueError):
                release.verify_record(output, record['version'], 3)
        with patch.object(release, 'source_digest', return_value='changed'), self.assertRaises(ValueError):
            release.verify_record(output, record['version'], 3)

    def publish_fixture(self, fail_upload=False):
        output, record = self.record()
        calls = []
        def api(method, path, token, body=None, upload=None):
            calls.append((method, path, body))
            if '/contents/' in path and method == 'GET':
                return {'sha': 'blob', 'content': base64.b64encode(b'{"latest":null,"history":[]}').decode()}
            if method == 'POST' and path.endswith('/releases'):
                return {'id': 9, 'upload_url': 'https://uploads.github.com/repos/ymltsh/SylphyMusic/releases/9/assets{?name,label}'}
            if upload and fail_upload:
                raise ValueError('simulated upload failure')
            return {}
        latest = {'version': record['version'], 'build': 3, 'name': 'test', 'notes': 'test', 'page': 'https://github.com/ymltsh/SylphyMusic/releases/tag/test'}
        def run(cmd, *args):
            return SimpleNamespace(stdout='' if cmd[1] == 'status' else 'a' * 40)
        return output, record, latest, calls, api, run

    def test_publish_uploads_before_visibility_and_updates_only_channel_manifest(self):
        output, record, latest, calls, api, run = self.publish_fixture()
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run', side_effect=run), patch.object(release, 'token_from_environment', return_value='synthetic-test-token'), redirect_stdout(io.StringIO()):
            release.publish(SimpleNamespace(no_push_manifest=False), record, output, 'v0.3.0-beta+3', latest)
        mutations = [(m, p, b) for m, p, b in calls if m != 'GET']
        self.assertTrue(mutations[0][2]['draft'])
        self.assertEqual(mutations[-2][0], 'PATCH')
        self.assertEqual(mutations[-1][1], '/repos/ymltsh/SylphyMusic/contents/version-beta.json')
        self.assertEqual(mutations[-1][2]['sha'], 'blob')
        self.assertFalse(any('version.json' in p for _, p, _ in mutations))

    def test_upload_failure_keeps_draft_and_does_not_advance_manifest(self):
        output, record, latest, calls, api, run = self.publish_fixture(True)
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run', side_effect=run), patch.object(release, 'token_from_environment', return_value='synthetic-test-token'), self.assertRaises(ValueError):
            release.publish(SimpleNamespace(no_push_manifest=False), record, output, 'v0.3.0-beta+3', latest)
        self.assertFalse(any(m in ('PUT', 'PATCH') for m, _, _ in calls))

    def test_resume_verifies_existing_assets_and_only_advances_manifest(self):
        output, record, latest, calls, original_api, run = self.publish_fixture()
        def api(method, path, token, body=None, upload=None):
            if '/releases/tags/' in path:
                calls.append((method, path, body))
                return {'id': 9, 'target_commitish': 'a' * 40, 'tag_name': 'v0.3.0-beta+3',
                        'draft': False, 'upload_url': 'https://uploads.github.com/test{?name}',
                        'assets': [{'name': n, 'digest': 'sha256:' + h, 'size': (output / n).stat().st_size}
                                   for n, h in record['sha256'].items()]}
            return original_api(method, path, token, body, upload)
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run', side_effect=run), patch.object(release, 'token_from_environment', return_value='synthetic-test-token'), redirect_stdout(io.StringIO()):
            release.publish(SimpleNamespace(no_push_manifest=False, resume=True), record, output, 'v0.3.0-beta+3', latest)
        self.assertEqual([m for m, _, _ in calls if m != 'GET'], ['PUT'])

    def test_resume_refuses_remote_asset_mismatch(self):
        output, record, latest, calls, original_api, run = self.publish_fixture()
        def api(method, path, token, body=None, upload=None):
            if '/releases/tags/' in path:
                return {'id': 9, 'target_commitish': 'a' * 40, 'tag_name': 'v0.3.0-beta+3',
                        'draft': True, 'upload_url': 'https://uploads.github.com/test{?name}',
                        'assets': [{'name': next(iter(record['sha256'])), 'digest': 'sha256:wrong', 'size': 1}]}
            return original_api(method, path, token, body, upload)
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run', side_effect=run), patch.object(release, 'token_from_environment', return_value='synthetic-test-token'), self.assertRaises(ValueError):
            release.publish(SimpleNamespace(no_push_manifest=False, resume=True), record, output, 'v0.3.0-beta+3', latest)
        self.assertFalse(any(m != 'GET' for m, _, _ in calls))

    def test_reused_compressed_packages_are_rescanned_without_printing_secrets(self):
        output = self.root / 'packages'
        output.mkdir()
        credentials = self.root / 'synthetic-credentials.txt'
        credentials.write_text('https://example.invalid\nsynthetic-user\nsynthetic-secret\n')
        package = output / 'test.apk'
        with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as apk:
            apk.writestr('assets/test', b'synthetic-secret')
        with self.assertRaises(ValueError) as error:
            release.scan_packages(output, {'artifacts': {'android_arm64': 'test.apk'}}, [str(credentials)])
        self.assertNotIn('synthetic-secret', str(error.exception))

    def test_remote_build_number_prevents_uninstallable_android_upgrade(self):
        output, record, latest, calls, original_api, run = self.publish_fixture()
        def api(method, path, token, body=None, upload=None):
            if '/contents/' in path and method == 'GET':
                old = {'latest': {'version': '0.2.0-beta', 'build': 100}, 'history': []}
                return {'sha': 'blob', 'content': base64.b64encode(json.dumps(old).encode()).decode()}
            return original_api(method, path, token, body, upload)
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run', side_effect=run), patch.object(release, 'token_from_environment', return_value='synthetic-test-token'), self.assertRaises(ValueError):
            release.publish(SimpleNamespace(no_push_manifest=False), record, output, 'v0.3.0-beta+3', latest)
        self.assertFalse(any(m != 'GET' for m, _, _ in calls))

    def test_pending_followups_do_not_block_stable_publication(self):
        output, record, latest, calls, api, run = self.publish_fixture()
        record['version'] = latest['version'] = '1.0.0'
        (self.root / 'docs').mkdir()
        gates = self.root / 'docs/RELEASE_GATES.md'
        gates.write_text('- [ ] Pending follow-up\n')
        with patch.object(release, 'api', side_effect=api), patch.object(release, 'run', side_effect=run), patch.object(release, 'token_from_environment', return_value='synthetic-test-token'), redirect_stdout(io.StringIO()):
            release.publish(SimpleNamespace(no_push_manifest=False), record, output, 'v1.0.0+3', latest)
        create = next(body for method, path, body in calls if method == 'POST' and path.endswith('/releases'))
        self.assertFalse(create['prerelease'])
        self.assertEqual(calls[-1][1], '/repos/ymltsh/SylphyMusic/contents/version.json')
        self.assertEqual(gates.read_text(), '- [ ] Pending follow-up\n')

    def test_unchecked_build_cannot_be_published(self):
        output, record = self.record()
        record['checks_passed'] = False
        with patch.object(release, 'run', return_value=SimpleNamespace(stdout='')), patch.object(release, 'api') as api, self.assertRaises(ValueError):
            release.publish(SimpleNamespace(no_push_manifest=False), record, output, 'v1.0.0+3', {})
        api.assert_not_called()


if __name__ == '__main__':
    unittest.main()
