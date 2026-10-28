#!/usr/bin/env python3
"""Local release preparation; remote writes require --publish. Python standard library only."""
import argparse
import base64
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = 'ymltsh/SylphyMusic'
VERSION = re.compile(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
PUB_VERSION = re.compile(r'^version:\s*(\d+\.\d+\.\d+(?:-beta2?)?)\+(\d+)\s*$', re.M)
ABIS = {'arm64-v8a': 'android_arm64', 'armeabi-v7a': 'android_armv7', 'x86_64': 'android_x64'}


def run(args, capture=False, input_text=None):
    return subprocess.run([str(a) for a in args], cwd=ROOT, check=True, text=True,
        encoding='utf-8', errors='replace', capture_output=capture, input=input_text)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_digest():
    names = run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], True).stdout
    result = hashlib.sha256()
    for name in sorted(set(filter(None, names.split('\0')))):
        if name in ('version.json', 'version-beta.json'):
            continue
        path = ROOT / name
        if path.is_file():
            result.update(name.encode('utf-8') + b'\0' + path.read_bytes() + b'\0')
    return result.hexdigest()


def compiler():
    candidates = [os.environ.get('INNO_SETUP_COMPILER'), shutil.which('ISCC.exe')]
    for folder in [os.environ.get('LOCALAPPDATA', '') + '/Programs',
                   os.environ.get('ProgramFiles(x86)', ''), os.environ.get('ProgramFiles', '')]:
        candidates.append(str(Path(folder) / 'Inno Setup 6/ISCC.exe'))
    for value in candidates:
        if value and Path(value).is_file():
            return value
    raise ValueError('Install Inno Setup 6 or set INNO_SETUP_COMPILER to ISCC.exe.')


def release_order(item):
    version = item['version']
    rank = 1 if version.endswith('-beta2') else 0 if version.endswith('-beta') else 2
    return (*map(int, version.split('-')[0].split('.')), rank, int(item['build']))


def manifest(previous, latest):
    history = list(previous.get('history', []))
    old = previous.get('latest')
    if old and (old['version'], old['build']) != (latest['version'], latest['build']):
        history.insert(0, old)
    history = [v for v in history if (v['version'], v['build']) != (latest['version'], latest['build'])]
    seen = set()
    unique = []
    for item in history:
        key = (item['version'], item['build'])
        if key not in seen:
            seen.add(key)
            unique.append(item)
    return {'latest': latest, 'history': unique}


def api(method, path, token, body=None, upload=None):
    url = path if path.startswith('https://uploads.github.com/') else 'https://api.github.com' + path
    headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
               'X-GitHub-Api-Version': '2026-03-10', 'User-Agent': 'SylphyMusic-release'}
    if upload is not None:
        data = upload.read_bytes()
        headers['Content-Type'] = 'application/octet-stream'
    else:
        data = None if body is None else json.dumps(body).encode('utf-8')
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise ValueError(f'GitHub {method} failed (HTTP {error.code}); no automatic write retry.') from None


def token_from_environment():
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if token:
        return token
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', GCM_INTERACTIVE='Never')
    result = subprocess.run(['git', 'credential', 'fill'], cwd=ROOT, text=True,
        input='protocol=https\nhost=github.com\n\n', capture_output=True, env=env)
    for line in result.stdout.splitlines():
        if line.startswith('password=') and result.returncode == 0:
            return line.split('=', 1)[1]
    raise ValueError('Set GH_TOKEN/GITHUB_TOKEN or configure GitHub Git credentials. Never pass tokens as arguments.')


def credential_needles(credential_files):
    needles = []
    for value in credential_files:
        lines = [v.strip() for v in Path(value).read_text(encoding='utf-8-sig').splitlines() if v.strip()]
        if len(lines) != 3:
            raise ValueError('Credential files must contain three nonempty lines.')
        for secret in [lines[0], lines[2]] + ([lines[1]] if len(lines[1]) >= 8 else []):
            needles.extend([secret.encode('utf-8'), secret.encode('utf-16-le')])
    return needles


def scan_packages(output, record, credential_files):
    needles = credential_needles(credential_files)
    if not needles:
        return
    def check(data):
        if any(n in data for n in needles):
            raise ValueError('Private-data scan failed in prepared release artifacts.')
    for name in record['artifacts'].values():
        path = output / name
        if path.suffix in ('.apk', '.zip'):
            with zipfile.ZipFile(path) as package:
                for entry in package.infolist():
                    if not entry.is_dir():
                        check(package.read(entry))
        else:
            check(path.read_bytes())


def scan_inputs(windows, apks, credential_files):
    needles = credential_needles(credential_files)
    def check(data):
        if any(n in data for n in needles):
            raise ValueError('Private-data scan failed; no release package may be published.')
    names = run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], True).stdout
    for name in filter(None, names.split('\0')):
        path = ROOT / name
        if path.is_file():
            check(path.read_bytes())
    for path in windows.rglob('*'):
        if path.is_file():
            check(path.read_bytes())
    for path in apks:
        with zipfile.ZipFile(path) as package:
            for entry in package.infolist():
                if not entry.is_dir():
                    check(package.read(entry))


def prepare(args, version, build, output):
    flutter = os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
    if not flutter:
        raise ValueError('Flutter is missing; set FLUTTER_BIN.')
    iscc = compiler()
    if not (ROOT / 'android/key.properties').is_file():
        raise ValueError('Production Android signing requires android/key.properties. Use build_review.ps1 for internal test signing.')
    if os.environ.get('SYLPHY_INTERNAL_DEBUG_SIGNING') == '1' or os.environ.get('SYLPHY_ALLOW_UNSIGNED_RELEASE') == '1':
        raise ValueError('Disable internal/unsigned signing flags before release preparation.')
    pubspec = ROOT / 'pubspec.yaml'
    pubspec.write_text(PUB_VERSION.sub(f'version: {version}+{build}', pubspec.read_text(encoding='utf-8'), count=1), encoding='utf-8')
    if not args.skip_checks:
        run([flutter, 'pub', 'get', '--enforce-lockfile'])
        run([sys.executable, 'tool/collect_licenses.py'])
    common = ['--release', f'--build-name={version}', f'--build-number={build}', f'--dart-define=SYLPHY_RELEASE_VERSION={version}']
    # Keep normal pub/plugin regeneration after integration_test builds.
    run([flutter, 'build', 'apk', '--split-per-abi', *common])
    run([flutter, 'build', 'windows', *common])
    windows = ROOT / 'build/windows/x64/runner/Release'
    apks = [ROOT / f'build/app/outputs/flutter-apk/app-{abi}-release.apk' for abi in ABIS]
    if not (windows / 'sylphy_music.exe').is_file() or not all(p.is_file() for p in apks):
        raise ValueError('Expected release binaries are missing.')
    run([sys.executable, 'tool/verify_android_signing.py', *apks])
    scan_inputs(windows, apks, args.credentials_file)
    output.mkdir(parents=True, exist_ok=True)
    artifacts = {}
    suffix = f'{version}-{build}'
    for abi, key in ABIS.items():
        target = output / f'sylphy-music-{suffix}-{abi}.apk'
        shutil.copyfile(ROOT / f'build/app/outputs/flutter-apk/app-{abi}-release.apk', target)
        artifacts[key] = target.name
    portable = output / f'sylphy-music-windows-{suffix}.zip'
    with zipfile.ZipFile(portable, 'w', zipfile.ZIP_DEFLATED) as package:
        for path in sorted(windows.rglob('*')):
            if path.is_file() and path.suffix.lower() not in ('.pdb', '.zip'):
                package.write(path, path.relative_to(windows))
        for name in ['LICENSE', 'docs/THIRD_PARTY_LICENSES.txt', 'docs/NATIVE_DEPENDENCIES.md']:
            package.write(ROOT / name, name)
        for path in (ROOT / 'docs/native_licenses').rglob('*'):
            if path.is_file():
                package.write(path, path.relative_to(ROOT))
    artifacts['windows_portable'] = portable.name
    # Inno packages the same scanned directory plus license documents.
    run([iscc, f'/DAppVersion={version}', f'/DAppNumericVersion={version.split("-")[0]}.{build}',
         f'/DReleaseSuffix={suffix}', f'/DSourceDir={windows}', f'/DOutputDir={output}',
         ROOT / 'installer/windows/SylphyMusic.iss'])
    installer = output / f'sylphy-music-setup-{suffix}.exe'
    if not installer.is_file():
        raise ValueError('Installer compiler did not produce the expected EXE.')
    artifacts['windows'] = installer.name
    hashes = {name: digest(output / name) for name in artifacts.values()}
    sums = output / 'SHA256SUMS.txt'
    sums.write_text(''.join(f'{value}  {name}\n' for name, value in sorted(hashes.items())), encoding='utf-8')
    hashes[sums.name] = digest(sums)
    record = {'version': version, 'build': build, 'source_sha256': source_digest(),
              'checks_passed': not args.skip_checks, 'artifacts': artifacts, 'sha256': hashes}
    (output / 'release-record.json').write_text(json.dumps(record, indent=2) + '\n', encoding='utf-8')
    return record


def verify_record(output, version, build):
    record = json.loads((output / 'release-record.json').read_text(encoding='utf-8'))
    if record['version'] != version or record['build'] != build:
        raise ValueError('Release record version/build mismatch.')
    if record['source_sha256'] != source_digest():
        raise ValueError('Sources changed since preparation; rebuild instead of reusing artifacts.')
    expected = set(ABIS.values()) | {'windows', 'windows_portable'}
    if set(record['artifacts']) != expected:
        raise ValueError('Release record is missing platform artifacts.')
    for name in [*record['artifacts'].values(), 'SHA256SUMS.txt']:
        if Path(name).name != name or digest(output / name) != record['sha256'].get(name):
            raise ValueError('Release artifact checksum mismatch.')
    return record


def publish(args, record, output, tag, latest):
    if run(['git', 'status', '--porcelain'], True).stdout.strip():
        raise ValueError('Commit local source/version changes separately before publishing; no source files are auto-committed.')
    if not record['checks_passed']:
        raise ValueError('Cannot publish artifacts prepared with --skip-checks.')
    # Follow-up checklists document remaining work; they do not gate releases.
    # Build-input records, production signing and artifact checks remain required.
    token = token_from_environment()
    prefix = f'/repos/{REPO}'
    sha = run(['git', 'rev-parse', 'HEAD'], True).stdout.strip()
    api('GET', prefix + '/commits/' + sha, token)  # The tag must identify remotely available source.
    filename = 'version-beta.json' if record['version'].endswith(('-beta', '-beta2')) else 'version.json'
    if not getattr(args, 'resume', False):
        refs = api('GET', prefix + '/git/matching-refs/tags/' + urllib.parse.quote(tag, safe=''), token)
        if refs:
            raise ValueError('The release tag already exists; inspect it and use --resume for a matching release.')
    remote = api('GET', prefix + '/contents/' + filename + '?ref=main', token)
    previous = json.loads(base64.b64decode(remote['content']))
    old = previous.get('latest')
    if old and release_order(old) >= release_order(latest):
        if getattr(args, 'resume', False) and old['version'] == latest['version'] and old['build'] == latest['build']:
            print('Remote update manifest already names this release; nothing to change.')
            return
        raise ValueError('Remote manifest is already this version or newer; inspect the existing release before retrying.')
    if old and old['build'] >= latest['build']:
        raise ValueError('New releases must exceed the remote build number for Android upgrades.')
    data = manifest(previous, latest)
    if getattr(args, 'resume', False):
        release = api('GET', prefix + '/releases/tags/' + urllib.parse.quote(tag, safe=''), token)
        if release['target_commitish'] != sha or release['tag_name'] != tag:
            raise ValueError('Existing release target does not match the prepared source commit.')
    else:
        # No blind retries or clobbering existing tags. Failure leaves a draft for inspection.
        release = api('POST', prefix + '/releases', token, {
            'tag_name': tag, 'target_commitish': sha, 'name': latest['name'], 'body': latest['notes'],
            'draft': True, 'prerelease': filename != 'version.json'})
    upload_base = release['upload_url'].split('{')[0]
    existing = {a['name']: a for a in release.get('assets', [])}
    if set(existing) - set(record['sha256']):
        raise ValueError('Existing draft contains unexpected assets; inspect them before publishing.')
    for name, checksum in record['sha256'].items():
        if name in existing:
            if existing[name].get('digest') != 'sha256:' + checksum or existing[name].get('size') != (output / name).stat().st_size:
                raise ValueError('Existing remote asset checksum/size mismatch; no assets were overwritten.')
            continue
        if not release.get('draft', True):
            raise ValueError('Published release is missing an asset; will not modify it.')
        api('POST', upload_base + '?name=' + urllib.parse.quote(name), token, upload=output / name)
    if release.get('draft', True):
        api('PATCH', prefix + f'/releases/{release["id"]}', token, {'draft': False})
    if not args.no_push_manifest:
        # GitHub Contents creates a commit changing exactly this file, guarded by its current blob SHA.
        api('PUT', prefix + '/contents/' + filename, token, {
            'message': f'Update release manifest to {tag}', 'branch': 'main', 'sha': remote['sha'],
            'content': base64.b64encode((json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')).decode('ascii')})
    print('Published ' + latest['page'])
    if args.no_push_manifest:
        print('Manifest was not pushed; use the local manifest candidate after publishing.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True, help='Three-part base version, e.g. 0.2.1')
    parser.add_argument('--build', type=int, help='Explicit build number, recommended for reproducibility')
    channel = parser.add_mutually_exclusive_group()
    channel.add_argument('--beta', action='store_true')
    channel.add_argument('--beta2', action='store_true')
    parser.add_argument('--name')
    parser.add_argument('--notes', default='')
    parser.add_argument('--notes-file', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--skip-build', action='store_true', help='Only reuse matching recorded and checksum-verified packages')
    parser.add_argument('--skip-checks', action='store_true', help='Skip local dependency/license collection checks for diagnosis; disables publication')
    parser.add_argument('--publish', action='store_true', help='Explicitly create and publish GitHub Release')
    parser.add_argument('--resume', action='store_true', help='Resume an existing matching draft/release without overwriting assets')
    parser.add_argument('--no-push-manifest', action='store_true')
    parser.add_argument('--credentials-file', action='append', default=[])
    if argv is None:
        argv = sys.argv[1:]
    if not argv:
        current = PUB_VERSION.search((ROOT / 'pubspec.yaml').read_text(encoding='utf-8'))
        chosen = input(f'Base version (current {current[1]}): ').strip() or current[1].split('-')[0]
        number = input(f'Build number [{int(current[2]) + 1}]: ').strip() or str(int(current[2]) + 1)
        kind = input('Channel: 1 stable / 2 beta / 3 beta2 [1]: ').strip() or '1'
        if kind not in ('1', '2', '3'):
            raise ValueError('Invalid release channel.')
        title = input('Release title (optional): ').strip()
        print('Release notes, blank line to finish:')
        lines = []
        while True:
            line = input()
            if not line:
                break
            lines.append(line)
        argv = ['--version', chosen, '--build', number, '--notes', '\n'.join(lines)]
        if kind != '1':
            argv.append('--beta' if kind == '2' else '--beta2')
        if title:
            argv.extend(['--name', title])
    args = parser.parse_args(argv)
    if not VERSION.fullmatch(args.version):
        raise ValueError('--version must be x.y.z without leading zeros.')
    current = PUB_VERSION.search((ROOT / 'pubspec.yaml').read_text(encoding='utf-8'))
    if not current:
        raise ValueError('Invalid pubspec version.')
    version = args.version + ('-beta2' if args.beta2 else '-beta' if args.beta else '')
    build = args.build if args.build is not None else int(current[2]) + (current[1] != version)
    if release_order({'version': version, 'build': build}) < release_order({'version': current[1], 'build': int(current[2])}):
        raise ValueError('Release version/build must not go backwards.')
    if build < int(current[2]) or (build == int(current[2]) and version != current[1]):
        raise ValueError('New releases must increase the build number; exact version/build can be reused.')
    if build < 1 or build > 65535:
        raise ValueError('Build must be 1–65535 (Windows resource version limit).')
    if any(int(n) > 65535 for n in args.version.split('.')):
        raise ValueError('Version components must fit Windows resource version fields.')
    tag = f'v{version}+{build}'
    output = ROOT / f'build/releases/{version}-{build}'
    latest = {'version': version, 'build': build, 'name': args.name or f'风灵音乐 v{version}',
              'date': date.today().isoformat(), 'notes': args.notes_file.read_text(encoding='utf-8') if args.notes_file else args.notes,
              'urls': {}, 'page': f'https://github.com/{REPO}/releases/tag/{tag}'}
    print(f'Version: {version}+{build}\nTag: {tag}\nOutput: {output}\nRemote publication: {args.publish}')
    if args.dry_run:
        return 0
    if args.resume and not (args.publish and args.skip_build):
        raise ValueError('--resume requires --publish --skip-build and matching local records.')
    if args.publish and args.skip_checks:
        raise ValueError('--publish cannot be used with --skip-checks.')
    record = verify_record(output, version, build) if args.skip_build else prepare(args, version, build, output)
    scan_packages(output, record, args.credentials_file)
    for key, name in record['artifacts'].items():
        latest['urls'][key] = f'https://github.com/{REPO}/releases/download/{urllib.parse.quote(tag, safe="")}/{name}'
    channel_file = 'version-beta.json' if args.beta or args.beta2 else 'version.json'
    previous = json.loads((ROOT / channel_file).read_text(encoding='utf-8'))
    (output / channel_file).write_text(json.dumps(manifest(previous, latest), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    if args.publish:
        publish(args, record, output, tag, latest)
    else:
        print('Prepared locally. No Release, tag, commit or push was created.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f'Release failed: {error}', file=sys.stderr)
        sys.exit(1)
