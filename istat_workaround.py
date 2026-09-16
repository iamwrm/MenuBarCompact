#!/usr/bin/env python3
"""Reversible macOS 27/iStat 7 helper-location workaround; no binary modification."""
import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import time
from pathlib import Path

LABEL = 'com.bjango.istatmenus.status'
HOME_DIR = Path.home()
SOURCE = HOME_DIR / 'Library/Application Support/iStat Menus 7/iStat Menus Menubar.app'
DEST = Path('/Applications/iStat Menus Menubar Compatibility.app')
AGENT = HOME_DIR / f'Library/LaunchAgents/{LABEL}.plist'
STATE = HOME_DIR / 'Library/Application Support/MenuBarCompact'
LEGACY_STATE = HOME_DIR / 'Library/Application Support/MenuBarRestrictionLab'
BACKUP = STATE / 'original-status-launchagent.plist'
MARKER = STATE / 'workaround.json'
DOMAIN = f'gui/{os.getuid()}'
REGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
EXECUTABLE = Path('Contents/MacOS/iStat Menus Menubar')


def migrate_legacy_state():
    """Keep rollback information from the diagnostic prototype without overwriting new state."""
    old_backup = LEGACY_STATE / BACKUP.name
    old_marker = LEGACY_STATE / MARKER.name
    if old_backup.exists() and old_marker.exists():
        STATE.mkdir(parents=True, exist_ok=True)
        for original, target in ((old_backup, BACKUP), (old_marker, MARKER)):
            if not target.exists():
                shutil.copy2(original, target)


def run(*args, check=True):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, timeout=30)
    if check and result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}): {result.stderr.strip()}')
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_agent():
    agent = plistlib.loads(AGENT.read_bytes())
    if agent.get('Label') != LABEL or agent.get('ProgramArguments'):
        raise RuntimeError('Unexpected launch-agent structure; left unchanged.')
    if agent.get('Program') not in (str(SOURCE / EXECUTABLE), str(DEST / EXECUTABLE)):
        raise RuntimeError('Unexpected helper path; left unchanged.')
    return agent


def write_agent(agent):
    temp = AGENT.with_suffix('.plist.menubarcompact-tmp')
    temp.write_bytes(plistlib.dumps(agent))
    os.chmod(temp, AGENT.stat().st_mode & 0o777)
    os.replace(temp, AGENT)


def reload_agent():
    result = run('launchctl', 'bootout', f'{DOMAIN}/{LABEL}', check=False)
    if result.returncode and run('launchctl', 'print', f'{DOMAIN}/{LABEL}', check=False).returncode == 0:
        raise RuntimeError(f'Could not unload helper: {result.stderr.strip()}')
    # bootout can return before the old process/Mach service finishes teardown.
    for _ in range(20):
        time.sleep(0.5)
        result = run('launchctl', 'bootstrap', DOMAIN, AGENT, check=False)
        if result.returncode == 0:
            return
        if run('launchctl', 'print', f'{DOMAIN}/{LABEL}', check=False).returncode == 0:
            return
    raise RuntimeError(f'Could not restart helper: {result.stderr.strip()}')


def install():
    agent = read_agent()
    info = plistlib.loads((SOURCE / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != LABEL:
        raise RuntimeError('Unexpected source bundle identity.')
    run('codesign', '--verify', '--strict', SOURCE)
    if DEST.exists() and not MARKER.exists():
        raise RuntimeError(f'Refusing to replace an unmanaged app: {DEST}')
    STATE.mkdir(parents=True, exist_ok=True)
    if not BACKUP.exists():
        if agent['Program'] != str(SOURCE / EXECUTABLE):
            raise RuntimeError('Original launch-agent backup is missing.')
        shutil.copy2(AGENT, BACKUP)
    staging = STATE / f'helper-staging-{time.time_ns()}.app'
    run('ditto', SOURCE, staging)
    run('codesign', '--verify', '--strict', staging)
    if DEST.exists():
        # Retain the previous managed copy for recovery rather than deleting it.
        shutil.move(str(DEST), str(STATE / f'previous-helper-{time.time_ns()}.app'))
    shutil.move(str(staging), str(DEST))
    run(REGISTER, '-f', DEST)
    before = dict(agent)
    try:
        agent['Program'] = str(DEST / EXECUTABLE)
        write_agent(agent)
        reload_agent()
    except Exception:
        write_agent(before)
        reload_agent()
        raise
    MARKER.write_text(json.dumps({'source': str(SOURCE), 'destination': str(DEST),
        'sourceVersion': info.get('CFBundleShortVersionString'),
        'sourceBuild': info.get('CFBundleVersion'),
        'executableSHA256': digest(SOURCE / EXECUTABLE)}, indent=2) + '\n')
    print('Installed: original signed helper copied to Applications; only launch-agent Program changed.')
    print('Thaw can remain running. After iStat updates, run install again to refresh the helper copy.')


def restore():
    if not BACKUP.exists():
        raise RuntimeError('No original launch-agent backup found.')
    agent = read_agent()
    original = plistlib.loads(BACKUP.read_bytes())
    agent['Program'] = original['Program']
    write_agent(agent)
    reload_agent()
    run(REGISTER, '-u', DEST, check=False)
    run(REGISTER, '-f', SOURCE)
    print('Restored original helper launch path. The inactive compatibility copy and backup are retained.')


def status():
    agent = read_agent()
    print('Launch-agent Program:', agent['Program'])
    print('Original backup:', BACKUP if BACKUP.exists() else 'not created')
    if DEST.exists():
        print('Helper executable matches original:', digest(SOURCE / EXECUTABLE) == digest(DEST / EXECUTABLE))
        print('Compatibility copy signature valid:', run('codesign', '--verify', '--strict', DEST, check=False).returncode == 0)
    result = run('launchctl', 'print', f'{DOMAIN}/{LABEL}', check=False)
    for line in result.stdout.splitlines():
        if any(key in line for key in ('state =', 'program =', 'pid =')):
            print(line.strip())


def ensure():
    """Idempotent refresh used by MenuBarCompact; leave absent iStat installations alone."""
    if not SOURCE.exists() or not AGENT.exists():
        print('iStat helper is not installed; no compatibility change needed.')
        return
    agent = read_agent()
    run('codesign', '--verify', '--strict', SOURCE)
    resources = Path('Contents/_CodeSignature/CodeResources')
    if (agent['Program'] == str(DEST / EXECUTABLE) and MARKER.exists()
            and (DEST / EXECUTABLE).exists()
            and digest(SOURCE / EXECUTABLE) == digest(DEST / EXECUTABLE)
            and (DEST / resources).exists()
            and (SOURCE / resources).read_bytes() == (DEST / resources).read_bytes()
            and (SOURCE / 'Contents/Info.plist').read_bytes() == (DEST / 'Contents/Info.plist').read_bytes()):
        run('codesign', '--verify', '--strict', DEST)
        job = run('launchctl', 'print', f'{DOMAIN}/{LABEL}', check=False)
        if job.returncode == 0 and f'program = {DEST / EXECUTABLE}' in job.stdout:
            print('iStat compatibility is ready; helper copy is current.')
            return
    install()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'restore', 'status', 'ensure'])
    args = parser.parse_args()
    try:
        migrate_legacy_state()
        {'install': install, 'restore': restore, 'status': status, 'ensure': ensure}[args.action]()
    except Exception as error:
        parser.exit(1, f'Error: {error}\n')
