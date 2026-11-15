"""Fetch the pinned upstream mpv Android runtime; never download an APK unchecked."""
from pathlib import Path
import hashlib,json,shutil,urllib.request,zipfile
ROOT=Path(__file__).resolve().parents[1]
TAG='2026-09-17'
DIGESTS={
 'arm64-v8a':'0b0e0a534dd6b8d2b117f06952e0600064ad97702e48bff02543e3e32107803d',
 'armeabi-v7a':'30c63f5528530f56cdece5d6466c749976f01bdcd8c8e67ae76e70a54b7243aa',
 'x86_64':'347cef5d0c2fe76ec95e19685597ad5d208e5309cc0642d51ae656b125ce1d07',
}
LIBS={'libmpv.so','libavcodec.so','libavdevice.so','libavfilter.so','libavformat.so','libavutil.so','libswresample.so','libswscale.so','libc++_shared.so'}
OUT=ROOT/'third_party/media_kit_libs_android_audio/android/src/main/jniLibs'
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def main():
 cache=ROOT/'.private/native/mpv-2026-09-17';cache.mkdir(parents=True,exist_ok=True)
 receipt=OUT/'runtime-sha256.json'
 if receipt.exists():
  saved=json.loads(receipt.read_text(encoding='utf-8'))
  if saved.get('tag')==TAG and saved.get('archives')==DIGESTS and len(saved.get('files',{}))==len(LIBS)*len(DIGESTS) and all((OUT/name).is_file() and digest(OUT/name)==value for name,value in saved['files'].items()):return
 files={}
 for abi,sha in DIGESTS.items():
  name=f'app-default-{abi}-release.apk';apk=cache/name
  legacy=ROOT/'.private/declick-native/mpv-android-arm64.apk'
  if abi=='arm64-v8a' and not apk.exists() and legacy.exists():shutil.copy2(legacy,apk)
  if not apk.exists() or digest(apk)!=sha:
   url=f'https://github.com/mpv-android/mpv-android/releases/download/{TAG}/{name}'
   temp=apk.with_suffix('.download')
   with urllib.request.urlopen(url,timeout=120) as response,temp.open('wb') as output:shutil.copyfileobj(response,output)
   if digest(temp)!=sha:temp.unlink();raise ValueError('Pinned mpv archive checksum mismatch')
   temp.replace(apk)
  with zipfile.ZipFile(apk) as package:
   for lib in sorted(LIBS):
    data=package.read(f'lib/{abi}/{lib}')
    if not data.startswith(b'\x7fELF'):raise ValueError('Invalid native library')
    target=OUT/abi/lib;target.parent.mkdir(parents=True,exist_ok=True)
    temp=target.with_suffix('.tmp');temp.write_bytes(data);temp.replace(target)
    files[f'{abi}/{lib}']=hashlib.sha256(data).hexdigest()
  print('Prepared pinned mpv runtime:',abi,flush=True)
 receipt.write_text(json.dumps({'tag':TAG,'archives':DIGESTS,'files':files},indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
