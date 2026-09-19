#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VENV="$ROOT/silero-venv"

if curl --silent --fail --max-time 1 "http://127.0.0.1:30179/health" >/dev/null 2>&1; then
  echo "Silero TTS already running at http://127.0.0.1:30179"
  exit 0
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  uv venv --python 3.12 "$VENV"
fi

if ! "$VENV/bin/python" -c "import numpy, torch" >/dev/null 2>&1; then
  uv pip install --python "$VENV/bin/python" numpy torch --index-url https://download.pytorch.org/whl/cpu
fi

exec "$VENV/bin/python" "$ROOT/silero_tts_server.py"
