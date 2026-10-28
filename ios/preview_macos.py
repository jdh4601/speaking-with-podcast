#!/usr/bin/env python3
"""Build a macOS preview of shared SwiftUI views without requiring an iOS SDK.

This does NOT compile or emulate iOS. Shared views use the same swipe deck;
app data lives in a separate preview directory.
"""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from toolchain import mac_swift_flags

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--open', action='store_true', help='Launch the macOS preview after building')
parser.add_argument('--pack', type=Path, help='Open an existing .podstudy file in the preview')
parser.add_argument('--typecheck-only', action='store_true')
args = parser.parse_args()

build = ROOT / 'build'
build.mkdir(exist_ok=True)
app = build / 'Podcast Study Preview.app'
with tempfile.TemporaryDirectory(prefix='podcast-ui-preview-') as temp:
    work = Path(temp)
    flags = mac_swift_flags(work)
    sources = []
    isolated_store = False
    for path in sorted((ROOT / 'PodcastStudy/App').glob('*.swift')):
        source = path.read_text()
        source = source.replace('.navigationBarTitleDisplayMode(.inline)', '')
        needle = '.appendingPathComponent("PodcastStudy", isDirectory: true)'
        if needle in source:
            source = source.replace(needle, '.appendingPathComponent("PodcastStudy-MacPreview", isDirectory: true)')
            isolated_store = True
        if path.name == 'PodcastStudyApp.swift':
            source = source.replace('ContentView().environmentObject(model)', 'ContentView().environmentObject(model).frame(minWidth: 390, idealWidth: 430, maxWidth: 560, minHeight: 740, idealHeight: 850)')
        output = work / path.name
        output.write_text(source)
        sources.append(output)
    if not isolated_store:
        raise SystemExit('Preview cannot identify its storage path; refusing to use the real app data.')
    sources += sorted((ROOT / 'PodcastStudy/Core').glob('*.swift'))
    command = ['swiftc', *flags, *map(str, sources)]
    if args.typecheck_only:
        subprocess.run([*command, '-typecheck'], check=True)
        print('PASS shared SwiftUI view typecheck on macOS (not an iOS build)')
    else:
        executable = app / 'Contents/MacOS/PodcastStudyPreview'
        executable.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([*command, '-o', str(executable)], check=True)
        resources = ROOT / 'PodcastStudy/Resources'
        if resources.exists():
            shutil.copytree(resources, app / 'Contents/Resources', dirs_exist_ok=True)
        info = plistlib.loads((ROOT / 'PodcastStudy/Info.plist').read_bytes())
        info.update(CFBundleIdentifier='com.jayden.podcaststudy.preview', CFBundleExecutable='PodcastStudyPreview', CFBundleName='PodcastStudyPreview', CFBundleDisplayName='Podcast Study Preview', CFBundleShortVersionString='1.0', CFBundleVersion='1', NSHighResolutionCapable=True, LSMinimumSystemVersion='14.0')
        for key in ['LSRequiresIPhoneOS', 'UIApplicationSceneManifest', 'UILaunchScreen', 'UISupportedInterfaceOrientations']:
            info.pop(key, None)
        # Preview doesn't claim to be the primary handler for users' study files.
        for document in info.get('CFBundleDocumentTypes', []):
            document['LSHandlerRank'] = 'Alternate'
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
        print(app)
        if args.open:
            command = ['open', '-a', str(app)]
            if args.pack:
                command.append(str(args.pack.expanduser().resolve(strict=True)))
            subprocess.run(command, check=True)
