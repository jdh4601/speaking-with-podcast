"""Generate a dependency-free Xcode project; no XcodeGen or CocoaPods required."""
from pathlib import Path
import hashlib
import plistlib

ROOT = Path(__file__).resolve().parent

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def quoted(value):
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

files = sorted((ROOT / 'PodcastStudy').rglob('*.swift'))
objects = []
def add(name, body):
    objects.append(f'{ident(name)} = {{ {body} }};')

for file in files:
    path = str(file.relative_to(ROOT))
    add(path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(path)}; sourceTree = "<group>";')
    add('build:' + path, f'isa = PBXBuildFile; fileRef = {ident(path)};')
add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PodcastStudy.app; sourceTree = BUILT_PRODUCTS_DIR;')
add('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(ident('build:' + str(f.relative_to(ROOT))) for f in files) + '); runOnlyForDeploymentPostprocessing = 0;')
add('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
add('products', f'isa = PBXGroup; children = ({ident("product")}); name = Products; sourceTree = "<group>";')
add('main', 'isa = PBXGroup; children = (' + ','.join([*(ident(str(f.relative_to(ROOT))) for f in files), ident('products')]) + '); sourceTree = "<group>";')
for mode in ['Debug', 'Release']:
    common = 'CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;'
    add('project:' + mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {common} }};')
    settings = common + ' CODE_SIGN_STYLE = Automatic; PRODUCT_BUNDLE_IDENTIFIER = com.jayden.podcaststudy; PRODUCT_NAME = "$(TARGET_NAME)"; INFOPLIST_FILE = PodcastStudy/Info.plist; TARGETED_DEVICE_FAMILY = 1; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; SUPPORTS_MACCATALYST = NO; MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1;'
    settings += ' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf;' if mode == 'Debug' else ' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
    add('target:' + mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} }};')
for scope in ['project', 'target']:
    add(scope + ':config', f'isa = XCConfigurationList; buildConfigurations = ({ident(scope + ":Debug")},{ident(scope + ":Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
add('target', f'isa = PBXNativeTarget; buildConfigurationList = {ident("target:config")}; buildPhases = ({ident("sources")},{ident("frameworks")},{ident("resources")}); buildRules = (); dependencies = (); name = PodcastStudy; productName = PodcastStudy; productReference = {ident("product")}; productType = "com.apple.product-type.application";')
add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {ident("target")} = {{ CreatedOnToolsVersion = 16.0; }}; }}; }}; buildConfigurationList = {ident("project:config")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = ko; hasScannedForEncodings = 0; knownRegions = (ko,en,Base); mainGroup = {ident("main")}; productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; targets = ({ident("target")});')
project = ROOT / 'PodcastStudy.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {ident("project")}; }}\n')
info = {
    'CFBundleDevelopmentRegion': 'ko', 'CFBundleDisplayName': 'Podcast Study',
    'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': '$(PRODUCT_NAME)', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
    'LSRequiresIPhoneOS': True, 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
    'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
    'LSSupportsOpeningDocumentsInPlace': True,
    'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Podcast Study Pack', 'CFBundleTypeRole': 'Viewer', 'LSHandlerRank': 'Owner', 'LSItemContentTypes': ['com.jayden.podcast-study.pack', 'com.jayden.podcast-study.progress']}],
    'UTExportedTypeDeclarations': [{'UTTypeIdentifier': 'com.jayden.podcast-study.pack', 'UTTypeDescription': 'Podcast Study Pack', 'UTTypeConformsTo': ['public.json'], 'UTTypeTagSpecification': {'public.filename-extension': ['podstudy'], 'public.mime-type': 'application/vnd.podcast-study+json'}}, {'UTTypeIdentifier': 'com.jayden.podcast-study.progress', 'UTTypeDescription': 'Podcast Study Progress Backup', 'UTTypeConformsTo': ['public.json'], 'UTTypeTagSpecification': {'public.filename-extension': ['podprogress'], 'public.mime-type': 'application/vnd.podcast-study-progress+json'}}]
}
(ROOT / 'PodcastStudy/Info.plist').write_bytes(plistlib.dumps(info, sort_keys=False))
scheme = project / 'xcshareddata/xcschemes/PodcastStudy.xcscheme'
scheme.parent.mkdir(parents=True, exist_ok=True)
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('target')}" BuildableName="PodcastStudy.app" BlueprintName="PodcastStudy" ReferencedContainer="container:PodcastStudy.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('target')}" BuildableName="PodcastStudy.app" BlueprintName="PodcastStudy" ReferencedContainer="container:PodcastStudy.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
