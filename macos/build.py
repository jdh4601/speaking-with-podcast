import pathlib,subprocess,plistlib,shutil,tempfile
root=pathlib.Path(__file__).resolve().parent
app=pathlib.Path.home()/'Applications/English Routine.app'
contents=app/'Contents';bin=contents/'MacOS';res=contents/'Resources'
bin.mkdir(parents=True,exist_ok=True);res.mkdir(exist_ok=True)
subprocess.run(['xcrun','clang','-fobjc-arc',str(root/'App.m'),'-o',str(bin/'EnglishRoutine'),'-framework','AppKit','-framework','WebKit'],check=True)
for name in ['server.py','audio_clips.py','align_words.py','youtube_tools.py','study_pack.py','conversation_report.py']:shutil.copy2(root/name,res/name)
shutil.copytree(root/'web',res/'web',dirs_exist_ok=True)
info={'CFBundleIdentifier':'com.jayden.englishroutine','CFBundleName':'English Routine','CFBundleDisplayName':'English Routine','CFBundleExecutable':'EnglishRoutine','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','CFBundleIconFile':'AppIcon','NSHighResolutionCapable':True,'LSMinimumSystemVersion':'13.0','NSPrincipalClass':'NSApplication','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True,'NSAllowsArbitraryLoadsInWebContent':True}}
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
with tempfile.TemporaryDirectory() as tmp:
    tmp=pathlib.Path(tmp);gen=tmp/'icon';subprocess.run(['xcrun','clang','-fobjc-arc',str(root/'Icon.m'),'-o',str(gen),'-framework','AppKit'],check=True);png=res/'AppIcon.png';subprocess.run([str(gen),str(png)],check=True)
    iconset=tmp/'AppIcon.iconset';iconset.mkdir()
    for size in [16,32,128,256,512]:
        for scale in [1,2]:
            name=f'icon_{size}x{size}'+('@2x' if scale==2 else '')+'.png'
            subprocess.run(['sips','-z',str(size*scale),str(size*scale),str(png),'--out',str(iconset/name)],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(res/'AppIcon.icns')],check=True)
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
print(app)
