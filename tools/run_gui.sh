#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
PY=python3
command -v python3 >/dev/null 2>&1 || PY=python
exec "$PY" gui/adda_test_gui_qt.py
