"""Collect resolved Dart package license texts. Native dependency audit is separate."""
import json
from pathlib import Path
import re
from urllib.parse import urljoin
from urllib.request import url2pathname

root=Path(__file__).resolve().parents[1]
config=root/'.dart_tool/package_config.json'
packages=json.loads(config.read_text(encoding='utf-8'))['packages']
sections=['Sylphy Music — resolved Dart package license inventory\nGenerated from pubspec.lock and package_config.json.\nNative libmpv/FFmpeg distribution obligations require the separate release audit.\n']
missing=[]
for package in sorted(packages,key=lambda item:item['name']):
    if package['name']=='sylphy_music':
        continue
    uri=urljoin(config.as_uri(),package['rootUri'])
    directory=Path(url2pathname(uri.removeprefix('file:')))
    files=[directory/name for name in ['LICENSE','LICENSE.md','LICENSE.txt','COPYING','NOTICE'] if (directory/name).is_file()]
    if not files and package['name'] in {'flutter','flutter_test','flutter_driver','flutter_web_plugins','integration_test','sky_engine','flutter_gpu','fuchsia_remote_debug_protocol'}:
        files=[path for path in [directory.parent.parent/'LICENSE',directory.parent/'LICENSE'] if path.is_file()][:1]
    if not files:
        missing.append(package['name'])
        continue
    pubspec=directory/'pubspec.yaml'
    version=re.search(r'^version:\s*(.+)$',pubspec.read_text(encoding='utf-8'),re.M) if pubspec.is_file() else None
    header=f"\n{'='*72}\n{package['name']} {version.group(1) if version else '(SDK)'}\n{'='*72}\n"
    sections.append(header+'\n'.join(path.read_text(encoding='utf-8',errors='replace') for path in files))
output=root/'docs/THIRD_PARTY_LICENSES.txt'
output.write_text('\n'.join(sections),encoding='utf-8')
print(f'Collected {len(sections)-1} package licenses.')
if missing:
    print('Require manual review: '+', '.join(missing))
