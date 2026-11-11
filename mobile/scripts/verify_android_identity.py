#!/usr/bin/env python3
"""Verify real debug artifacts can participate in the same Wear Data Layer."""
from pathlib import Path
import os
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
phone = root / 'apps/mobile/build/app/outputs/flutter-apk/app-debug.apk'
watch = root / 'native/wearos/app/build/outputs/apk/debug/app-debug.apk'
expected = 'app.crispycrust.mobile'
sdk = Path(os.environ.get('ANDROID_SDK_ROOT', os.environ.get('ANDROID_HOME', '/usr/local/lib/android/sdk')))

def tool(name):
    located = shutil.which(name)
    if located:
        return located
    candidates = sorted((sdk / 'build-tools').glob(f'*/{name}'))
    if not candidates:
        raise SystemExit(f'Android SDK tool {name} is required to verify built identities.')
    return str(candidates[-1])

def metadata(apk):
    if not apk.is_file():
        raise SystemExit(f'Build the actual artifact before identity verification: {apk}')
    package_output = subprocess.check_output([tool('aapt'), 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"^package: name='([^']+)'", package_output, re.M)
    if not package:
        raise SystemExit(f'Cannot read package identity from {apk.name}')
    signer_output = subprocess.check_output([tool('apksigner'), 'verify', '--print-certs', str(apk)], text=True)
    signers = set(re.findall(r'Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)', signer_output))
    if not signers:
        raise SystemExit(f'No verified signing certificate in {apk}')
    return package.group(1), {value.lower() for value in signers}

phone_id, phone_signers = metadata(phone)
watch_id, watch_signers = metadata(watch)
if phone_id != expected or watch_id != expected:
    raise SystemExit(f'Data Layer requires identical configured application IDs: phone={phone_id}, watch={watch_id}')
if phone_signers != watch_signers:
    raise SystemExit('Phone and Wear debug artifacts have different signing certificates; Data Layer cannot connect.')
print(f'Actual phone and Wear APKs both use {expected} and matching verified debug signing certificates.')
print('This verifies packaging prerequisites, not physical watch pairing or release signing.')
