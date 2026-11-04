"""Sign an explicitly selected local review bundle and refresh runtime hashes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

MACHO = {bytes.fromhex(s) for s in ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def sign(app, identity):
    runtime = app / 'Contents/Resources/PulseRuntime'
    # Symlinks point to their already inventoried in-bundle targets.
    binaries = []
    for path in runtime.rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MACHO:
                    binaries.append(path)
    for path in sorted(binaries):
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity,
                        '--timestamp', '--options', 'runtime', str(path)], check=True)
    manifest = runtime / 'manifest.json'
    value = json.loads(manifest.read_bytes())
    for relative in value['files']:
        value['files'][relative] = hashlib.sha256((runtime / relative).read_bytes()).hexdigest()
    manifest.write_text(json.dumps(value, sort_keys=True) + '\n')
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity,
                    '--timestamp', '--options', 'runtime', str(app)], check=True)
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict',
                    '--verbose=2', str(app)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('identity')
    args = parser.parse_args()
    sign(args.app, args.identity)
