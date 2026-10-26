#!/usr/bin/env python3
"""Package a locally built helper; stop the running helper before rebuilding."""
from pathlib import Path
import shutil,plistlib,subprocess,sys,os
root=Path(sys.argv[1]).resolve();app=Path(sys.argv[2]).expanduser().absolute();c=app/'Contents'
if not (root/'build-vgf/sunshine').is_file() or not (root/'build-vgf/assets').is_dir():
    raise SystemExit('Build Sunshine and its assets before packaging')
if app.exists():
    with (c/'Info.plist').open('rb') as f: existing=plistlib.load(f)
    if existing.get('CFBundleIdentifier') != 'net.tarucy.videogamefilter.sunshine':
        raise SystemExit('Refusing to replace an unrelated app')
    shutil.rmtree(app)  # Only this verified generated helper bundle.

(c/'MacOS').mkdir(parents=True,exist_ok=True);(c/'Resources').mkdir(exist_ok=True)
shutil.copy2(root/'build-vgf/sunshine',c/'MacOS/sunshine')
shutil.copytree(root/'build-vgf/assets',c/'Resources/assets',dirs_exist_ok=True)
info=dict(CFBundleIdentifier='net.tarucy.videogamefilter.sunshine',CFBundleName='VGF Sunshine',CFBundleDisplayName='VGF Sunshine',CFBundleExecutable='sunshine',CFBundlePackageType='APPL',CFBundleShortVersionString='2025.628.4510',CFBundleVersion='1',LSUIElement=True,NSMicrophoneUsageDescription='Capture the Elgato game audio for Moonlight streaming.',NSLocalNetworkUsageDescription='Stream Video Game Filter to your paired Moonlight devices.')
with (c/'Info.plist').open('wb') as f:plistlib.dump(info,f)
frameworks=c/'Frameworks';frameworks.mkdir(exist_ok=True)
identity=os.environ.get('CODE_SIGN_IDENTITY','Developer ID Application: eunkyu lee (WBL49792F2)')
visited=set()
def bundle_libraries(binary):
    if binary in visited:return
    visited.add(binary)
    links=subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines()[1:]
    for line in links:
        old=line.strip().split(' (')[0]
        if not old.startswith(('/opt/homebrew/','/usr/local/')):continue
        target=frameworks/Path(old).name
        if not target.exists():
            shutil.copy2(old,target);target.chmod(0o755)
            subprocess.run(['install_name_tool','-id','@executable_path/../Frameworks/'+target.name,str(target)],check=True)
            bundle_libraries(target)
        subprocess.run(['install_name_tool','-change',old,'@executable_path/../Frameworks/'+target.name,str(binary)],check=True)
bundle_libraries(c/'MacOS/sunshine')
for library in frameworks.glob('*.dylib'):
    subprocess.run(['codesign','--force','--options','runtime','--timestamp','--sign',identity,str(library)],check=True)
subprocess.run(['codesign','--force','--options','runtime','--timestamp','--sign',identity,'--entitlements',str(Path(__file__).with_name('Entitlements.plist')),str(app)],check=True)

subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('Signed and verified VGF Sunshine helper with bundled libraries')
