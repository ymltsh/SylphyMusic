"""Package the current application source and assets without ignored/private files."""
from pathlib import Path
import subprocess,sys,zipfile
ROOT=Path(__file__).resolve().parents[1]
def package(output):
 names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode('utf-8').split('\0')
 excluded={'.jks','.keystore','.p12','.aar','.jar','.so','.dll','.exe','.apk','.pdb'}
 output.parent.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
  for name in sorted(set(filter(None,names))):
   p=ROOT/name
   if not p.is_file() or p.suffix.lower() in excluded:continue
   if name.startswith(('.private/','build/','.dart_tool/','.git/')) or name=='android/key.properties':raise ValueError('Private source archive input')
   archive.write(p,'SylphyMusic/'+name)
 print('Packaged application source:',output.name)
if __name__=='__main__':package(Path(sys.argv[1]))
