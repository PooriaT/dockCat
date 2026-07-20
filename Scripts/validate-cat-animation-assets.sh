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
for c in m.get('clips', []):
    for f in c.get('frameNames', []):
        if '/' in f or '\\' in f or '..' in f or f.startswith('/'): errors.append(f'invalid frame basename {f}')
        if not any((root/m.get('atlasName','') ).with_suffix('.atlas').joinpath(f + ext).exists() for ext in ('','.png')):
            errors.append(f'missing frame image {f}')
if errors:
    for e in errors: print('error:', e, file=sys.stderr)
    sys.exit(1)
print('cat animation asset validation passed')
PY
