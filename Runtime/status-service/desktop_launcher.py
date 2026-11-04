#!/usr/bin/env python3
"""Preview or explicitly launch the reviewed local desktop permission pilot."""
import argparse
import os
from pathlib import Path
import stat
import uuid
from desktop_cohort import birth, initialize_launch_source, app_pids

APP = '/Applications/ChatGPT.app/Contents/MacOS/ChatGPT'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--launch', action='store_true', help='requires normal full app quit first')
    args = parser.parse_args()
    wrapper = Path(__file__).resolve().with_name('codex-desktop-wrapper')
    source = Path.home() / '.codex/pulsestick-permissions/desktop.json'
    print('Opt-in desktop permission observation. No approval capability.')
    print(f'Wrapper: {wrapper}\nPrivate metadata: {source}')
    print('Requires reviewed observer installation and normal full desktop quit. Ordinary app launch bypasses the wrapper; restore observer configuration for full rollback.')
    if not args.launch:
        return
    try:
        running = app_pids(APP)
    except ValueError:
        parser.error('desktop process inspection failed')
    if running:
        parser.error('desktop is running; quit normally before using this launcher')
    source.parent.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = source.parent.lstat()
    if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700 or not os.access(wrapper, os.X_OK)):
        parser.error('unsafe metadata directory or missing executable wrapper')
    cohort, app_birth = uuid.uuid4().hex, birth(os.getpid())
    try:
        initialize_launch_source(source, cohort, os.getpid(), app_birth)
    except (OSError, ValueError, KeyError, TypeError):
        parser.error('previous runtime evidence needs reviewed recovery; no app started')
    environment = {**os.environ, 'CODEX_CLI_PATH': str(wrapper),
                   'BAMBOOX_PERMISSION_SOURCE': str(source),
                   'BAMBOOX_PERMISSION_COHORT': cohort,
                   'BAMBOOX_PERMISSION_APP_PID': str(os.getpid()),
                   'BAMBOOX_PERMISSION_APP_BIRTH': app_birth}
    os.execve(APP, [APP], environment)


if __name__ == '__main__':
    main()
