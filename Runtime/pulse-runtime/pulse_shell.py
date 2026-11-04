"""Packaged Pulse startup uses its own observer metadata directory."""
from pathlib import Path
from desktop_shell_core import main


if __name__ == '__main__':
    main(Path.home() / 'Library/Application Support/BambooPulse/Observer/desktop.json')
