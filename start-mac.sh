#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$HERE/mail_mcp.py" --config "${1:-$HERE/config.json}"
