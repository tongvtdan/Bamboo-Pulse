"""Packaged Pulse observes only backends launched by the desktop collector's app."""
import os
import sys

import desktop_native_v3 as observer


def main():
    # Shells and tools inside a chat inherit the desktop exports. Starting a
    # second CLI from there must not enroll that CLI in the desktop's cohort.
    if (not os.environ.get('BAMBOOX_PERMISSION_COHORT') or
            os.environ.get('BAMBOOX_PERMISSION_APP_PID') != str(os.getppid())):
        os.execv(observer.REAL_CLI, [observer.REAL_CLI, *sys.argv[1:]])
    return observer.main()


if __name__ == '__main__':
    sys.exit(main())
