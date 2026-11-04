#!/usr/bin/env python3
"""Stage the explicit Pulse-only source closure and the pinned macOS arm64 Python distribution."""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


ARCHIVE_SHA256 = "a04567046dafa60fb75c07054f8c2a8203127689ae5d1c5b8a681ac5e4e28ace"


def stage(destination, python, notices):
    destination, python = Path(destination), Path(python)
    if destination.exists() or destination.is_symlink():
        raise ValueError('OUTPUT_EXISTS')
    # All third-party code comes from a supplied distribution. No network or host fallback.
    if not (python / 'bin/python3').is_file() or not (python / 'lib').is_dir():
        raise ValueError('STANDALONE_PYTHON_REQUIRED')
    sources = {p.stem: p for p in (ROOT / 'status-service').glob('*.py')}
    sources.update({p.stem: p for p in Path(__file__).parent.glob('*.py') if p.name != 'package.py'})
    sources['desktop_shell_core'] = sources['desktop_shell']
    selected, pending = {}, ['setup', 'monitor', 'pulse_shell', 'desktop_entry', 'desktop_startup_setup', 'hook']
    while pending:
        name = pending.pop()
        if name in selected:
            continue
        source = sources[name]
        if source.is_symlink():
            raise ValueError('SOURCE_SYMLINK')
        selected[name] = source
        for node in ast.walk(ast.parse(source.read_text())):
            imports = [a.name.split('.')[0] for a in node.names] if isinstance(node, ast.Import) else (
                [node.module.split('.')[0]] if isinstance(node, ast.ImportFrom) and node.module else [])
            for dependency in imports:
                if dependency in sources and dependency not in selected:
                    pending.append(dependency)
                elif dependency not in sources and dependency not in sys.stdlib_module_names:
                    raise ValueError('UNBUNDLED_IMPORT:' + dependency)
    destination.mkdir(parents=True)
    try:
        shutil.copytree(python, destination / 'python', symlinks=True,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'site-packages', 'test', 'tests'))
        shutil.copytree(notices, destination / 'licenses' / 'python-distribution')
        shutil.copy2(ROOT.parent / 'LICENSE', destination / 'licenses' / 'Bamboo-Pulse.txt')
        target = destination / 'status-service'
        target.mkdir()
        for name, source in selected.items():
            shutil.copy2(source, target / (name + '.py'))
        shutil.copy2(target / 'pulse_shell.py', target / 'desktop_shell.py')
        shutil.copy2(target / 'desktop_entry.py', target / 'desktop_bridge.py')
        shutil.copy2(ROOT / 'status-service/codex-desktop-wrapper', target)
        (target / 'codex-desktop-wrapper').chmod(0o755)
        # Validate relocation, standard-library extensions and absence of host import paths.
        subprocess.run([str(destination / 'python/bin/python3'), '-I', '-S', '-B', '-c',
                        'import os,sqlite3,ssl,ctypes,sys; assert os.path.samefile(sys.prefix, sys.argv[1])',
                        str(destination / 'python')], check=True, capture_output=True)
        files = {}
        for path in sorted(destination.rglob('*')):
            if path.is_symlink() and not path.resolve().is_relative_to(destination.resolve()):
                raise ValueError('EXTERNAL_PYTHON_LINK')
            if path.is_file():
                files[str(path.relative_to(destination))] = hashlib.sha256(path.read_bytes()).hexdigest()
        (destination / 'manifest.json').write_text(json.dumps({'version': 1, 'files': files}, sort_keys=True) + '\n')
        return sorted(selected)
    except BaseException:
        shutil.rmtree(destination)
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--python-archive', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory() as directory:
        scratch = Path(directory)
        # Hash and extract the same private copy, even if the input path changes.
        archive = scratch / 'runtime.tar.zst'
        shutil.copyfile(args.python_archive, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != ARCHIVE_SHA256:
            parser.exit(2, 'Python archive SHA-256 does not match the pinned release.\n')
        subprocess.run(['/usr/bin/tar', '-xf', str(archive), '-C', directory,
                        'python/install', 'python/licenses'], check=True)
        modules = stage(args.output, scratch / 'python/install', scratch / 'python/licenses')
        print(json.dumps({'modules': modules}))
