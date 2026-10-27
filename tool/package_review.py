"""Package freshly built main-entrypoint internal review apps for internal review only.

Run both normal flutter builds after integration tests, which overwrite outputs.
Optional private credential files contain URL, username and password on 3 lines.
The scan emits filenames only and never copies credential files into packages.
"""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--mode', choices=['debug', 'optimized'], default='debug')
parser.add_argument('--credentials-file', action='append', default=[])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
optimized = args.mode == 'optimized'
windows = root / ('build/windows/x64/runner/Release' if optimized else 'build/windows/x64/runner/Debug')
apks = [(root / f'build/app/outputs/flutter-apk/app-{abi}-release.apk', abi) for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']] if optimized else [(root / 'build/app/outputs/flutter-apk/app-debug.apk', 'universal')]
if not (windows / 'sylphy_music.exe').is_file() or not all(path.is_file() for path, _ in apks):
    raise SystemExit('Build the matching Windows and Android applications first.')

needles = []
for filename in args.credentials_file:
    lines = Path(filename).read_text(encoding='utf-8-sig').splitlines()
    lines = [line.strip() for line in lines if line.strip()]
    if len(lines) != 3:
        raise SystemExit('Credential input must have exactly three nonempty lines.')
    # Short usernames are often ordinary language in dependencies; URL/password
    # are always checked, and longer identifiers are checked as well.
    values = [lines[0], lines[2]] + ([lines[1]] if len(lines[1]) >= 8 else [])
    for value in values:
        needles.extend([value.encode('utf-8'), value.encode('utf-16-le')])

def check(label, data):
    if any(needle in data for needle in needles):
        raise SystemExit(f'Private-data check failed in {label}; no package created.')

tracked = subprocess.check_output(
    ['git', 'ls-files', '-z'], cwd=root
).decode('utf-8').split('\0')
for filename in filter(None, tracked):
    check(filename, (root / filename).read_bytes())
files = sorted(path for path in windows.rglob('*') if path.is_file() and (not optimized or path.suffix.lower() != '.pdb'))
for path in files:
    check(str(path.relative_to(root)), path.read_bytes())
for apk, abi in apks:
    with zipfile.ZipFile(apk) as package:
        for entry in package.infolist():
            if not entry.is_dir():
                check(f'APK:{abi}:{entry.filename}', package.read(entry))

output = root / 'build/internal-review'
output.mkdir(parents=True, exist_ok=True)
label = 'release-internal' if optimized else 'debug'
windows_zip = output / f'SylphyMusic-windows-{label}.zip'
with zipfile.ZipFile(windows_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as package:
    for path in files:
        package.write(path, Path('SylphyMusic') / path.relative_to(windows))
    for filename in ['LICENSE', 'docs/THIRD_PARTY_LICENSES.txt', 'docs/NATIVE_DEPENDENCIES.md']:
        package.write(root / filename, Path('SylphyMusic') / filename)
    for path in sorted((root / 'docs/native_licenses').rglob('*')):
        if path.is_file():
            package.write(path, Path('SylphyMusic') / path.relative_to(root))
artifacts = [windows_zip]
for apk, abi in apks:
    name = f'SylphyMusic-android-{label}-{abi}.apk' if optimized else 'SylphyMusic-android-debug.apk'
    target = output / name
    shutil.copyfile(apk, target)
    artifacts.append(target)
(output / f'README-{args.mode}.txt').write_text(
    'Sylphy Music — internal review only\n'
    'Windows: extract the entire ZIP, then run SylphyMusic/sylphy_music.exe.\n'
    'Keep the data directory and DLLs beside the executable.\n'
    'Android: choose arm64-v8a for modern 64-bit ARM phones; armeabi-v7a for older 32-bit ARM; x86_64 for emulator testing.\n'
    'Signing follows local Android configuration; without a production key, optimized internal builds explicitly use the test key.\n'
    'No private credentials or personal media are included. Formal release gates still apply.\n',
    encoding='utf-8',
)
hashes = []
for path in artifacts:
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    hashes.append(f'{digest}  {path.name}')
(output / f'SHA256SUMS-{args.mode}.txt').write_text('\n'.join(hashes) + '\n', encoding='utf-8')
print(f'Checked {len(list(filter(None, tracked)))} tracked files and application contents.')
for path in artifacts:
    print(f'{path.name}: {path.stat().st_size / 1_000_000:.2f} MB')
print(f'Internal review packages: {output}')
