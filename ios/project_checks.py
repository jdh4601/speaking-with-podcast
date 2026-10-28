#!/usr/bin/env python3
"""Check Xcode references and document registration without an iOS SDK."""
import json
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
project_path = ROOT / 'PodcastStudy.xcodeproj/project.pbxproj'
project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project_path)]))
objects = project['objects']
root = objects[project['rootObject']]
assert root['isa'] == 'PBXProject'
targets = [objects[key] for key in root['targets']]
assert len(targets) == 1 and targets[0]['productType'] == 'com.apple.product-type.application'
target = targets[0]
phases = [objects[key] for key in target['buildPhases']]
source_phase = next(phase for phase in phases if phase['isa'] == 'PBXSourcesBuildPhase')
references = [objects[objects[key]['fileRef']] for key in source_phase['files']]
paths = [reference['path'] for reference in references]
expected = {str(path.relative_to(ROOT)) for path in (ROOT / 'PodcastStudy').rglob('*.swift')}
assert len(paths) == len(set(paths)), 'Duplicate Swift build sources'
assert set(paths) == expected, f'Xcode sources differ from disk: {set(paths) ^ expected}'
for path in paths:
    assert (ROOT / path).is_file(), f'Missing Swift source: {path}'
configs = objects[target['buildConfigurationList']]['buildConfigurations']
for key in configs:
    settings = objects[key]['buildSettings']
    assert settings['INFOPLIST_FILE'] == 'PodcastStudy/Info.plist'
    assert float(settings['IPHONEOS_DEPLOYMENT_TARGET']) >= 17
    assert settings['TARGETED_DEVICE_FAMILY'] == '1'
print(f'PASS Xcode target references all {len(paths)} Swift sources')

with (ROOT / 'PodcastStudy/Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
declarations = {item['UTTypeIdentifier']: item for item in info['UTExportedTypeDeclarations']}
roles = set(value for document in info['CFBundleDocumentTypes'] for value in document['LSItemContentTypes'])
for suffix, identifier in [('podstudy', 'com.jayden.podcast-study.pack'), ('podprogress', 'com.jayden.podcast-study.progress')]:
    assert identifier in roles and identifier in declarations
    declaration = declarations[identifier]
    assert 'public.json' in declaration['UTTypeConformsTo']
    assert suffix in declaration['UTTypeTagSpecification']['public.filename-extension']
assert info['LSSupportsOpeningDocumentsInPlace'] is True
assert info['UIFileSharingEnabled'] is True
print('PASS study-pack and progress-backup file registration')

scheme = ET.parse(ROOT / 'PodcastStudy.xcodeproj/xcshareddata/xcschemes/PodcastStudy.xcscheme').getroot()
for reference in scheme.iter('BuildableReference'):
    assert reference.attrib['BlueprintIdentifier'] in objects
    assert objects[reference.attrib['BlueprintIdentifier']]['isa'] == 'PBXNativeTarget'
print('PASS shared launch scheme references the app target')
