"""Local Swift compiler helpers; never modify the installed developer tools."""
import json
from pathlib import Path
import subprocess


def mac_swift_flags(work):
    toolchain = Path(subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    duplicate = toolchain / 'usr/include/swift/module.modulemap'
    bridge = toolchain / 'usr/include/swift/bridging.modulemap'
    flags = []
    if duplicate.exists() and bridge.exists() and 'module SwiftBridging' in duplicate.read_text() and 'module SwiftBridging' in bridge.read_text():
        (work / 'empty.modulemap').write_text('')
        overlay = work / 'overlay.json'
        overlay.write_text(json.dumps({'version': 0, 'roots': [{'type': 'file', 'name': str(duplicate), 'external-contents': str(work / 'empty.modulemap')}]}))
        flags += ['-vfsoverlay', str(overlay)]
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path', '--sdk', 'macosx'], text=True).strip()
    return flags + ['-sdk', sdk, '-module-cache-path', str(work / 'cache')]
