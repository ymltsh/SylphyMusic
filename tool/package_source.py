"""Package the current application source and assets without ignored/private files."""
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_SUFFIXES = {'.jks', '.keystore', '.p12', '.aar', '.jar', '.so', '.dll', '.apk', '.exe', '.pdb'}


def write_application_sources(archive):
    tracked_and_unignored = subprocess.check_output(
        ['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT,
    ).decode('utf-8')
    paths = tracked_and_unignored.split('\0')
    for name in sorted(set(filter(None, paths))):
        path = ROOT / name
        if not path.is_file() or path.suffix.lower() in EXCLUDED_SUFFIXES:
            continue
        if name.startswith(('.private/', 'build/', '.dart_tool/', '.git/')) or name == 'android/key.properties':
            raise ValueError('Private source archive input')
        archive.write(path, 'SylphyMusic/' + name)


def package(output):
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
        write_application_sources(archive)
    print('Packaged application source:', output.name)


if __name__ == '__main__':
    package(Path(sys.argv[1]))
