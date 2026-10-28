"""Verify APK signatures against the repository's public production certificate."""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def find_apksigner():
    configured = shutil.which('apksigner')
    if configured:
        return Path(configured)
    sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
    local = ROOT / 'android/local.properties'
    if not sdk and local.is_file():
        for line in local.read_text(encoding='utf-8').splitlines():
            if line.startswith('sdk.dir='):
                sdk = re.sub(r'\\(.)', r'\1', line.split('=', 1)[1])
                break
    if sdk:
        folders = [p for p in (Path(sdk) / 'build-tools').glob('*')
                   if re.fullmatch(r'\d+(?:\.\d+)*', p.name)]
        for folder in sorted(folders, key=lambda p: tuple(map(int, p.name.split('.'))), reverse=True):
            candidate = folder / ('apksigner.bat' if os.name == 'nt' else 'apksigner')
            if candidate.is_file():
                return candidate
    raise ValueError('Cannot find apksigner; pass --apksigner or configure the Android SDK.')


def verify(apksigner, apk, expected):
    result = subprocess.run([str(apksigner), 'verify', '--verbose', '--print-certs', str(apk)],
                            capture_output=True, text=True, encoding='utf-8', errors='replace')
    if result.returncode:
        raise ValueError(f'APK signature verification failed: {apk.name}')
    signers = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]{64})\s*$',
                         result.stdout, flags=re.M)
    if [value.lower() for value in signers] != [expected]:
        raise ValueError(f'Production certificate mismatch: {apk.name}')
    print(f'PASS {apk.name}: {expected}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', nargs='+', type=Path)
    parser.add_argument('--apksigner', type=Path)
    args = parser.parse_args()
    pem = (ROOT / 'android/signing/release-cert.pem').read_text(encoding='ascii')
    der = base64.b64decode(''.join(line for line in pem.splitlines() if not line.startswith('---')),
                          validate=True)
    expected = hashlib.sha256(der).hexdigest()
    apksigner = args.apksigner or find_apksigner()
    for apk in args.apk:
        if not apk.is_file():
            raise ValueError(f'APK does not exist: {apk}')
        verify(apksigner, apk, expected)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(str(error)) from None
