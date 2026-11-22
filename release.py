#!/usr/bin/env python3
"""Build and publish Sylphy Music, then push and verify the update manifests."""
import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = 'ymltsh/SylphyMusic'
VERSION_BASE = r'(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)'
VERSION = re.compile(VERSION_BASE)
OPENLIST_VERSION = re.compile(VERSION_BASE + r'-openlist\.[1-9]\d*')
PUB_VERSION = re.compile(r'^version:[ \t]*(\d+\.\d+\.\d+(?:-beta2?|-openlist\.\d+)?)\+(\d+)[ \t]*$', re.M)
OPENLIST_BRANCH = 'feature/android-openlist-lite'
OPENLIST_SOURCE = 'sylphy-music-openlist-source.zip'
OPENLIST_APK = 'sylphy-music-arm64-v8a.apk'
ABIS = {'arm64-v8a': 'android_arm64', 'armeabi-v7a': 'android_armv7', 'x86_64': 'android_x64'}


def run(args, capture=False, input_text=None, *, cwd=None):
    return subprocess.run([str(a) for a in args], cwd=cwd or ROOT, check=True, text=True,
        encoding='utf-8', errors='replace', capture_output=capture, input=input_text)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


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
    base, _, suffix = version.partition('-')
    if suffix.startswith('openlist.'):
        return (*map(int, base.split('.')), int(suffix.split('.')[1]), int(item['build']))
    rank = 1 if version.endswith('-beta2') else 0 if version.endswith('-beta') else 2
    return (*map(int, base.split('.')), rank, int(item['build']))


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
    for name in record.get('sha256', record['artifacts'].values()):
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
    if not needles:
        return

    def check(data):
        if any(n in data for n in needles):
            raise ValueError('Private-data scan failed; no release package may be published.')
    names = run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], True).stdout
    for name in filter(None, names.split('\0')):
        path = ROOT / name
        if path.is_file():
            check(path.read_bytes())
    if windows:
        for path in windows.rglob('*'):
            if path.is_file():
                check(path.read_bytes())
    for path in apks:
        with zipfile.ZipFile(path) as package:
            for entry in package.infolist():
                if not entry.is_dir():
                    check(package.read(entry))


def openlist_source_archive(output, version, build, source):
    from tool.package_source import write_application_sources

    destination = output / OPENLIST_SOURCE
    apk_native_library = 'lib/arm64-v8a/libgojni.so'
    if source is None:
        previous = read_manifest(ROOT / 'version-openlist.json')['latest']
        if not previous:
            raise ValueError('Specify --openlist-source-archive for the bundled OpenList library.')
        previous_output = ROOT / f'build/releases/{previous["version"]}-{previous["build"]}'
        if not (previous_output / OPENLIST_APK).is_file():
            raise ValueError('Previous APK is unavailable; specify --openlist-source-archive.')
        with zipfile.ZipFile(output / OPENLIST_APK) as apk, zipfile.ZipFile(previous_output / OPENLIST_APK) as old_apk:
            with apk.open(apk_native_library) as native, old_apk.open(apk_native_library) as old_native:
                if hashlib.file_digest(native, 'sha256').digest() != hashlib.file_digest(old_native, 'sha256').digest():
                    raise ValueError('OpenList native library changed; specify its --openlist-source-archive.')
        source = previous_output / OPENLIST_SOURCE
    if not source.is_file():
        raise ValueError(f'OpenList source archive is missing: {source}. Specify --openlist-source-archive.')

    # Replace the app snapshot while retaining the corresponding backend and frontend.
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        candidate = Path(temporary) / OPENLIST_SOURCE
        with zipfile.ZipFile(source) as upstream, zipfile.ZipFile(candidate, 'w', zipfile.ZIP_DEFLATED) as archive:
            names = upstream.namelist()
            frontends = [name for name in names if re.fullmatch(r'OpenList-Frontend-[\w.]+-source\.tar\.gz', name)]
            if 'OpenList/go.mod' not in names or 'OpenList/openlistlib/bridge.go' not in names or not frontends:
                raise ValueError('OpenList source archive must include the backend, bridge and frontend source.')
            for entry in upstream.infolist():
                if entry.filename.startswith('OpenList/') or entry.filename in frontends:
                    if '..' in Path(entry.filename).parts or '\\' in entry.filename:
                        raise ValueError('Invalid path in OpenList source archive.')
                    with upstream.open(entry) as content, archive.open(entry.filename, 'w') as member:
                        shutil.copyfileobj(content, member)
            archive.writestr('README-SOURCE.txt',
                f'Source snapshot for Sylphy Music {version}+{build}.\n'
                'SylphyMusic/ contains the local application source.\n'
                'OpenList/ contains the backend, Go module locks, embedded frontend and native bridge.\n'
                f'Frontend source: {", ".join(frontends)}.\n'
                'See SylphyMusic/docs/OPENLIST_LITE_ANDROID.md for build instructions.\n')
            write_application_sources(archive)
        candidate.replace(destination)


def prepare(args, version, build, output):
    flutter = os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
    if not flutter:
        raise ValueError('Flutter is missing; set FLUTTER_BIN.')
    iscc = None if args.openlist else compiler()
    if not (ROOT / 'android/key.properties').is_file():
        raise ValueError('Production Android signing requires android/key.properties. Use build_review.ps1 for internal test signing.')
    if os.environ.get('SYLPHY_INTERNAL_DEBUG_SIGNING') == '1' or os.environ.get('SYLPHY_ALLOW_UNSIGNED_RELEASE') == '1':
        raise ValueError('Disable internal/unsigned signing flags before release preparation.')
    run([sys.executable, 'tool/collect_licenses.py'])
    common = ['--release', f'--build-name={version}', f'--build-number={build}', f'--dart-define=SYLPHY_RELEASE_VERSION={version}']
    # Keep normal pub/plugin regeneration after integration_test builds.
    if args.openlist:
        run([flutter, 'build', 'apk', '--split-per-abi', '--target-platform', 'android-arm64', *common])
        apk = ROOT / 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
        if not apk.is_file():
            raise ValueError('Expected ARM64 release APK is missing.')
        scan_inputs(None, [apk], args.credentials_file)
        output.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(apk, output / OPENLIST_APK)
        openlist_source_archive(output, version, build, args.openlist_source_archive)
        return existing_packages(output, version, build)
    run([flutter, 'build', 'apk', '--split-per-abi', *common])
    run([flutter, 'build', 'windows', *common])
    windows = ROOT / 'build/windows/x64/runner/Release'
    apks = [ROOT / f'build/app/outputs/flutter-apk/app-{abi}-release.apk' for abi in ABIS]
    if not (windows / 'sylphy_music.exe').is_file() or not all(p.is_file() for p in apks):
        raise ValueError('Expected release binaries are missing.')
    scan_inputs(windows, apks, args.credentials_file)
    output.mkdir(parents=True, exist_ok=True)
    for abi in ABIS:
        target = output / f'sylphy-music-{abi}.apk'
        shutil.copyfile(ROOT / f'build/app/outputs/flutter-apk/app-{abi}-release.apk', target)
    portable = output / 'sylphy-music-windows.zip'
    with zipfile.ZipFile(portable, 'w', zipfile.ZIP_DEFLATED) as package:
        for path in sorted(windows.rglob('*')):
            if path.is_file() and path.suffix.lower() not in ('.pdb', '.zip'):
                package.write(path, path.relative_to(windows))
        for name in ['LICENSE', 'docs/THIRD_PARTY_LICENSES.txt', 'docs/NATIVE_DEPENDENCIES.md']:
            package.write(ROOT / name, name)
        for path in (ROOT / 'docs/native_licenses').rglob('*'):
            if path.is_file():
                package.write(path, path.relative_to(ROOT))
    # Inno packages the same scanned directory plus license documents.
    run([iscc, f'/DAppVersion={version}', f'/DAppNumericVersion={version.split("-")[0]}.{build}',
         f'/DSourceDir={windows}', f'/DOutputDir={output}',
         ROOT / 'installer/windows/SylphyMusic.iss'])
    installer = output / 'sylphy-music-setup.exe'
    if not installer.is_file():
        raise ValueError('Installer compiler did not produce the expected EXE.')
    run([sys.executable, 'tool/package_source.py', output / 'sylphy-music-source.zip'])
    return existing_packages(output, version, build)


def existing_packages(output, version, build):
    if OPENLIST_VERSION.fullmatch(version):
        artifacts = {'android_arm64': OPENLIST_APK}
        names = [OPENLIST_APK, OPENLIST_SOURCE]
    else:
        artifacts = {key: f'sylphy-music-{abi}.apk' for abi, key in ABIS.items()}
        artifacts.update(windows='sylphy-music-setup.exe',
                         windows_portable='sylphy-music-windows.zip')
        names = list(artifacts.values())
        if (output / 'sylphy-music-source.zip').is_file():
            names.append('sylphy-music-source.zip')
    missing = [name for name in names if not (output / name).is_file()]
    if missing:
        raise ValueError(f'Release artifacts are missing in {output}: {", ".join(missing)}')
    hashes = {name: digest(output / name) for name in names}
    sums = output / 'SHA256SUMS.txt'
    sums.write_text(''.join(f'{value}  {name}\n' for name, value in sorted(hashes.items())), encoding='utf-8')
    hashes[sums.name] = digest(sums)
    return {'version': version, 'build': build, 'artifacts': artifacts, 'sha256': hashes}


def verify_published_release(token, tag, latest, output, hashes, *, prerelease=False):
    prefix = f'/repos/{REPO}'
    remote = api('GET', prefix + '/releases/tags/' + urllib.parse.quote(tag, safe=''), token)
    if (remote['draft'] or remote['prerelease'] != prerelease or
            remote['name'] != latest['name'] or remote['body'] != latest['notes']):
        raise ValueError('Published release status, title or notes do not match.')
    assets = remote['assets']
    if len(assets) != len(hashes) or {a['name'] for a in assets} != set(hashes):
        raise ValueError('Published release attachments do not match.')
    for asset in assets:
        name = asset['name']
        if (asset['size'] != (output / name).stat().st_size or
                asset.get('digest') != 'sha256:' + hashes[name]):
            raise ValueError(f'Published attachment size or SHA-256 mismatch: {name}')
    if not prerelease and api('GET', prefix + '/releases/latest', token)['tag_name'] != tag:
        raise ValueError('Published stable release is not Latest.')
    print(f'PASS: release status, notes and {len(assets)} attachment digests.', flush=True)


def read_manifest(path):
    return json.loads(path.read_text(encoding='utf-8'))


def manifest_targets(openlist, beta):
    if openlist:
        return [
            (ROOT, OPENLIST_BRANCH, ('version-openlist.json', 'version.json')),
            (ROOT.parent / 'sylphy_music', 'main', ('version-openlist.json',)),
        ]
    return [(ROOT, 'main', ('version-beta.json' if beta else 'version.json',))]


def check_publish_targets(targets, *, no_push):
    for root, branch, files in targets:
        if run(['git', 'branch', '--show-current'], True, cwd=root).stdout.strip() != branch:
            raise ValueError(f'{root} must be checked out on {branch}.')
        if no_push:
            continue
        if run(['git', 'status', '--porcelain', '--', *files], True, cwd=root).stdout.strip():
            raise ValueError(f'{branch} already has uncommitted update manifest changes.')
        ref = f'refs/heads/{branch}'
        remote = run(['git', 'ls-remote', 'origin', ref], True, cwd=root).stdout.split()
        local = run(['git', 'rev-parse', 'HEAD'], True, cwd=root).stdout.strip()
        if remote != [local, ref]:
            raise ValueError(f'{branch} must match origin/{branch} before a manifest-only push.')


def verify_manifests(targets, latest, *, wait_seconds=45):
    pending = {}
    for _, branch, files in targets:
        for filename in files:
            raw = f'https://raw.githubusercontent.com/{REPO}/{branch}/{filename}'
            pending[raw] = f'{branch}/{filename} (raw)'
            pending['https://hub.wgen.top/' + raw] = f'{branch}/{filename} (accelerated)'
    deadline = time.monotonic() + wait_seconds
    while pending:
        for url, label in list(pending.items()):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                request = urllib.request.Request(url, headers={
                    'User-Agent': 'SylphyMusic-release', 'Cache-Control': 'no-cache'})
                with urllib.request.urlopen(request, timeout=min(8, remaining)) as response:
                    data = json.load(response)
            except (OSError, ValueError):
                continue
            if isinstance(data, dict) and data.get('latest') == latest:
                print(f'PASS: {label}.', flush=True)
                del pending[url]
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        if pending:
            time.sleep(min(5, remaining))
    return list(pending.values())


def check_manifest_delivery(targets, latest, *, openlist):
    pending = verify_manifests(targets, latest)
    if pending:
        command = 'python release.py --verify-only'
        version = latest['version']
        if openlist:
            command += ' --openlist'
        elif version.endswith(('-beta', '-beta2')):
            command += ' --' + version.rsplit('-', 1)[1]
            version = version.split('-')[0]
        command += f' --version {version} --build {latest["build"]}'
        print('Manifest verification pending for: ' + ', '.join(pending), file=sys.stderr)
        print(f'To check delivery again: {command}', file=sys.stderr)
        return 2
    return 0


def publish(args, record, output, tag, latest):
    version = record['version']
    openlist = bool(OPENLIST_VERSION.fullmatch(version))
    beta = version.endswith(('-beta', '-beta2'))
    prerelease = openlist or beta
    targets = manifest_targets(openlist, beta)
    check_publish_targets(targets, no_push=args.no_push)
    root, branch, files = targets[0]
    previous = read_manifest(root / files[0])
    old = previous.get('latest')
    if old and release_order(old) >= release_order(latest):
        raise ValueError('The update manifest is already this version or newer.')
    if old and old['build'] >= latest['build']:
        raise ValueError('New releases must increase the build number.')
    data = json.dumps(manifest(previous, latest), ensure_ascii=False, indent=2) + '\n'

    token = token_from_environment()
    prefix = f'/repos/{REPO}'
    refs = api('GET', prefix + '/git/matching-refs/tags/' + urllib.parse.quote(tag, safe=''), token)
    if any(ref['ref'] == 'refs/tags/' + tag for ref in refs):
        raise ValueError('The release tag already exists; no existing assets were overwritten.')
    release = api('POST', prefix + '/releases', token, {
        'tag_name': tag, 'target_commitish': branch, 'name': latest['name'], 'body': latest['notes'],
        'draft': True, 'prerelease': prerelease})
    print(f'Created draft for {tag} (release ID {release["id"]}).', flush=True)
    upload_base = release['upload_url'].split('{')[0]
    for name in record['sha256']:
        asset = api('POST', upload_base + '?name=' + urllib.parse.quote(name), token, upload=output / name)
        if (asset['size'] != (output / name).stat().st_size or
                asset.get('digest') != 'sha256:' + record['sha256'][name]):
            raise ValueError(f'Uploaded attachment mismatch: {name}; draft retained.')
    api('PATCH', prefix + f'/releases/{release["id"]}', token, {
        'draft': False, 'make_latest': 'false' if prerelease else 'true'})
    print('Release published: ' + latest['page'], flush=True)
    verify_published_release(token, tag, latest, output, record['sha256'], prerelease=prerelease)
    for root, branch, files in targets:
        for filename in files:
            (root / filename).write_text(data, encoding='utf-8')
        if not args.no_push:
            run(['git', 'add', '--', *files], cwd=root)
            message = f'Update release manifest to {tag}'
            if branch == OPENLIST_BRANCH:
                message += ' [skip ci]'
            run(['git', 'commit', '--only', '-m', message, '--', *files], cwd=root)
            run(['git', 'push', 'origin', f'HEAD:refs/heads/{branch}'], cwd=root)
            print(f'Manifest pushed: {branch} ({", ".join(files)}).', flush=True)
    if args.no_push:
        print('Release succeeded (manifest not pushed): ' + latest['page'], flush=True)
        return 0
    result = check_manifest_delivery(targets, latest, openlist=openlist)
    if result == 0:
        print('Release succeeded: ' + latest['page'], flush=True)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', help='Base version x.y.z, or x.y.z-openlist.N with --openlist')
    parser.add_argument('--build', type=int, help='Explicit build number, recommended for reproducibility')
    channel = parser.add_mutually_exclusive_group()
    channel.add_argument('--beta', action='store_true')
    channel.add_argument('--beta2', action='store_true')
    channel.add_argument('--openlist', action='store_true', help='Release OpenList-Lite for Android ARM64')
    parser.add_argument('--name')
    parser.add_argument('--notes', default='')
    parser.add_argument('--notes-file', type=Path)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--dry-run', action='store_true')
    mode.add_argument('--verify-only', action='store_true', help='Check remote manifests against the local latest release')
    parser.add_argument('--skip-build', action='store_true', help='Reuse the release artifacts for this version')
    parser.add_argument('--openlist-source-archive', type=Path, help='ZIP with the matching OpenList backend and frontend source')
    parser.add_argument('--skip-checks', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--no-push', action='store_true', help='Update the local manifest without committing or pushing it')
    parser.add_argument('--credentials-file', action='append', default=[])
    if argv is None:
        argv = sys.argv[1:]
    if not argv:
        current = PUB_VERSION.search((ROOT / 'pubspec.yaml').read_text(encoding='utf-8'))
        if not current:
            raise ValueError('Invalid pubspec version.')
        if OPENLIST_VERSION.fullmatch(current[1]):
            parser.error('For OpenList, specify --openlist --version x.y.z-openlist.N --build NUMBER.')
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
    if args.openlist_source_archive and (not args.openlist or args.skip_build or args.verify_only):
        parser.error('--openlist-source-archive is only used for an OpenList build.')
    if not args.version and not args.verify_only:
        parser.error('--version is required to publish or preview a release.')
    pattern = OPENLIST_VERSION if args.openlist else VERSION
    if args.version and not pattern.fullmatch(args.version):
        parser.error('--version must be x.y.z-openlist.N with --openlist, or x.y.z otherwise.')
    suffix = '-beta2' if args.beta2 else '-beta' if args.beta else ''
    version = args.version + suffix if args.version else None

    current = PUB_VERSION.search((ROOT / 'pubspec.yaml').read_text(encoding='utf-8'))
    if not current:
        raise ValueError('Invalid pubspec version.')
    if args.openlist != bool(OPENLIST_VERSION.fullmatch(current[1])):
        raise ValueError('Run the OpenList channel from the OpenList worktree and other channels from main.')
    if args.verify_only:
        targets = manifest_targets(args.openlist, args.beta or args.beta2)
        root, _, files = targets[0]
        latest = read_manifest(root / files[0])['latest']
        if not latest or (version and latest['version'] != version) or (
                args.build is not None and latest['build'] != args.build):
            raise ValueError('The local update manifest does not contain the requested latest release.')
        print(f'Checking manifest delivery for {latest["version"]}+{latest["build"]}.', flush=True)
        return check_manifest_delivery(targets, latest, openlist=args.openlist)

    build = args.build if args.build is not None else int(current[2]) + 1
    if release_order({'version': version, 'build': build}) < release_order({'version': current[1], 'build': int(current[2])}):
        raise ValueError('Release version/build must not go backwards.')
    if build < int(current[2]) or (build == int(current[2]) and version != current[1]):
        raise ValueError('New releases must increase the build number; exact version/build can be reused.')
    if build < 1 or build > (2100000000 if args.openlist else 65535):
        raise ValueError('Build must fit the Android version code or Windows resource version.')
    if not args.openlist and any(int(n) > 65535 for n in args.version.split('.')):
        raise ValueError('Version components must fit Windows resource version fields.')
    tag = f'v{version}+{build}'
    output = ROOT / f'build/releases/{version}-{build}'
    default_name = f'风灵音乐 OpenList-Lite 特别版 {version} (arm64-v8a)' if args.openlist else f'风灵音乐 v{version}'
    latest = {'version': version, 'build': build, 'name': args.name or default_name,
              'date': date.today().isoformat(), 'notes': args.notes_file.read_text(encoding='utf-8') if args.notes_file else args.notes.replace('\\n', '\n'),
              'urls': {}, 'page': f'https://github.com/{REPO}/releases/tag/{tag}'}
    print(f'Version: {version}+{build}\nTag: {tag}\nOutput: {output}')
    if args.dry_run:
        return 0
    pubspec = ROOT / 'pubspec.yaml'
    pubspec.write_text(PUB_VERSION.sub(f'version: {version}+{build}', pubspec.read_text(encoding='utf-8'), count=1), encoding='utf-8')
    record = existing_packages(output, version, build) if args.skip_build else prepare(args, version, build, output)
    apk_paths = [output / name for key, name in record['artifacts'].items() if key in ABIS.values()]
    run([sys.executable, 'tool/verify_android_signing.py', *apk_paths])
    scan_packages(output, record, args.credentials_file)
    for key, name in record['artifacts'].items():
        latest['urls'][key] = f'https://github.com/{REPO}/releases/download/{urllib.parse.quote(tag, safe="")}/{name}'
    return publish(args, record, output, tag, latest) or 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f'Release failed: {error}', file=sys.stderr)
        sys.exit(1)
