#!/usr/bin/env python3
"""The remote preflight must reject missing data before opening the game."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[1] / 'scripts/safebench.sh').read_text()
start = source.index('  have_pak0=0\n')
end = source.index('  # gentle pre-clean:', start)
remote = source[start:end].replace(r'\"', '"').replace(r'\$', '$')
with tempfile.TemporaryDirectory(prefix='q3-bench-data-') as tmp:
    root = Path(tmp)
    (root / 'baseq3').mkdir()
    for name in [None, 'pak1.pk3', 'pak0.pk3', 'PAK0.PK3']:
        if name:
            (root / 'baseq3' / name).touch()
        result = subprocess.run(['bash', '-c', remote], cwd=root, capture_output=True, text=True)
        missing = name in [None, 'pak1.pk3']
        assert result.returncode == (9 if missing else 0), result
        assert ('Missing readable' in result.stdout) == missing
        if name:
            (root / 'baseq3' / name).unlink()
print('PASS: missing main archive refused; lower/upper-case archive accepted')
