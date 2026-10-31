"""Integration check: briefly offset DPI, then verify the running agent restores it.

Run only with the mouse-speed-keeper LaunchAgent active. The original DPI is
restored in finally even if automatic recovery fails.
"""
import json
import pathlib
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
binary = root / '.build/mouse-speed'
original = root / 'mouse-config.json'
config = json.loads(original.read_text())
config = {key: config[key] for key in ('identity', 'dpi')}

def run(*args):
    result = subprocess.run([str(binary), *map(str, args)],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout

with tempfile.TemporaryDirectory(prefix='mouse-speed-check-') as directory:
    temporary = pathlib.Path(directory) / 'offset.json'
    baseline = pathlib.Path(directory) / 'baseline.json'
    observed = pathlib.Path(directory) / 'observed.json'
    baseline.write_text(json.dumps(config))
    temporary.write_text(json.dumps({**config, 'dpi': config['dpi'] + 100}))
    try:
        print(run('apply', temporary), flush=True)
        recovered = False
        for _ in range(3):
            time.sleep(5)
            run('capture', observed)
            actual = json.loads(observed.read_text())
            if actual == config:
                recovered = True
                break
        if not recovered:
            raise RuntimeError('Background DPI recovery was not observed')
        print(f"PASS: background agent restored {config['dpi']} DPI", flush=True)
    finally:
        print(run('apply', baseline), flush=True)
