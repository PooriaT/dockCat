#!/usr/bin/env bash
set -euo pipefail
DIR="${1:-Sources/DockCat/Resources/CatAnimations}"
MANIFEST="$DIR/manifest.json"
SOURCES="$DIR/ASSET-SOURCES.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "warning: optional cat animation manifest not present at $DIR" >&2
  exit 0
fi
if [[ ! -f "$SOURCES" ]]; then
  echo "error: ASSET-SOURCES.json is required when a cat animation manifest is present" >&2
  exit 1
fi
python3 - "$DIR" <<'PY'
import json, pathlib, sys
root=pathlib.Path(sys.argv[1])
m=json.loads((root/'manifest.json').read_text())
required=['sleep','wake','pickUp','turnToPresentation','walkCarry','present','wait','turnHome','walkHome','settle']
errors=[]
if m.get('schemaVersion') != 1: errors.append('unsupported schemaVersion')
clips={c.get('id'): c for c in m.get('clips', [])}
for r in required:
    if r not in clips: errors.append(f'missing required clip {r}')
canvas=m.get('logicalCanvasSize', {})
scale=m.get('nativeScale')
expected=None
if isinstance(canvas.get('width'), (int,float)) and isinstance(canvas.get('height'), (int,float)) and isinstance(scale, int) and scale > 0:
    expected=(int(canvas['width']*scale), int(canvas['height']*scale))
else:
    errors.append('invalid logicalCanvasSize or nativeScale')
atlas_dir=(root/m.get('atlasName','')).with_suffix('.atlas')
def png_size(path):
    data=path.read_bytes()[:24]
    if len(data) < 24 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError('not a PNG')
    return (int.from_bytes(data[16:20], 'big'), int.from_bytes(data[20:24], 'big'))
for c in m.get('clips', []):
    for f in c.get('frameNames', []):
        if '/' in f or '\\' in f or '..' in f or f.startswith('/'):
            errors.append(f'invalid frame basename {f}')
        candidates=[atlas_dir.joinpath(f + ext) for ext in ('','.png')]
        existing=next((candidate for candidate in candidates if candidate.exists()), None)
        if existing is None:
            errors.append(f'missing frame image {f}')
            continue
        if expected and existing.suffix.lower() == '.png':
            try:
                actual=png_size(existing)
                if actual != expected:
                    errors.append(f'dimension mismatch for {f}: expected {expected[0]}x{expected[1]}, got {actual[0]}x{actual[1]}')
            except Exception:
                errors.append(f'invalid PNG metadata for {f}')
if errors:
    for e in errors: print('error:', e, file=sys.stderr)
    sys.exit(1)
print('cat animation asset validation passed')
PY
