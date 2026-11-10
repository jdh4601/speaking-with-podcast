#!/usr/bin/env python3
"""Run project checks and an iOS Simulator build when its SDK is installed."""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--require-ios', action='store_true', help='Fail if the iOS Simulator SDK is unavailable')
args = parser.parse_args()
commands = [
    [sys.executable, '-m', 'unittest', 'discover', '-s', 'macos', '-p', 'test_*.py', '-q'],
    ['node', '--check', 'macos/web/study-export.js'],
    ['node', 'macos/test_study_export_ui.cjs'],
    ['node', '--check', 'macos/web/conversation-core.js'],
    ['node', '--check', 'macos/web/conversation-trend.js'],
    ['node', '--check', 'macos/web/conversation.js'],
    ['node', '--check', 'macos/web/mistake-review.js'],
    ['node', '--check', 'macos/web/app.js'],
    ['node', 'macos/test_conversation_ui.cjs'],
    [sys.executable, 'ios/project_checks.py'],
    [sys.executable, 'ios/check.py'],
    [sys.executable, 'ios/preview_macos.py', '--typecheck-only'],
]
for command in commands:
    subprocess.run(command, cwd=ROOT.parent, check=True)
probe = subprocess.run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], capture_output=True, text=True)
if probe.returncode:
    message = 'iOS Simulator SDK is not installed. Device/simulator build and runtime remain unverified.'
    if args.require_ios:
        raise SystemExit(message)
    print('SKIP ' + message)
else:
    subprocess.run(['swift', 'test'], cwd=ROOT, check=True)
    subprocess.run(['xcodebuild', '-project', 'PodcastStudy.xcodeproj', '-scheme', 'PodcastStudy', '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(ROOT / 'build/DerivedData'), 'CODE_SIGNING_ALLOWED=NO', 'build'], cwd=ROOT, check=True)
    print('PASS iOS Simulator build (runtime testing is a separate step)')
