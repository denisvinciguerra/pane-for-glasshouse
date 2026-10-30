#!/bin/bash
# Records sanitized GET-only fixtures from a Glasshouse server.
# Usage: scripts/record-fixtures.sh HOST [PORT] [standby]
#   standby: records only /api/stats -> stats-standby.json (run while the TV is in standby)
set -euo pipefail

HOST="${1:?usage: record-fixtures.sh HOST [PORT] [standby]}"
PORT="${2:-8080}"
MODE="${3:-full}"
BASE="http://$HOST:$PORT"
OUT="$(cd "$(dirname "$0")/.." && pwd)/PaneKit/Tests/PaneKitTests/Fixtures"
mkdir -p "$OUT"

sanitize_json() {
python3 -I -c '
import json, re, sys
MAC = re.compile(r"\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b")
IP = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?!\w|\.\d)")
def scrub(s):
    return IP.sub("192.0.2.10", MAC.sub("00:11:22:33:44:55", s))
def walk(v, key=None):
    if isinstance(v, dict):
        return {k: walk(x, k) for k, x in v.items()}
    if isinstance(v, list):
        return [walk(x, key) for x in v]
    if isinstance(v, str):
        if key == "mac": return "00:11:22:33:44:55"
        if key == "ssid": return "home-wifi"
        if key in ("address", "origin"): return "192.0.2.10"
        return scrub(v)
    return v
json.dump(walk(json.load(sys.stdin)), sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
'
}

record_json() { # path name
  curl -s -m 10 "$BASE$1" | sanitize_json > "$OUT/$2.json"
  echo "recorded $2.json"
}

if [ "$MODE" = "standby" ]; then
  record_json "/api/stats" stats-standby
  exit 0
fi

record_json "/api/stats" stats
record_json "/api/caps" caps
record_json "/api/picture" picture
record_json "/api/game" game
record_json "/api/audio?with=settings" audio
record_json "/api/hdmi" hdmi
record_json "/api/lgsettings?section=hdmi,devices" lgsettings-hdmi-devices

curl -s -m 10 "$BASE/" | python3 -I -c '
import re, sys
s = sys.stdin.read()
s = re.sub(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?!\w|\.\d)", "192.0.2.10", s)
s = re.sub(r"\b(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}\b", "00:11:22:33:44:55", s)
sys.stdout.write(s)
' > "$OUT/ui.html"
echo "recorded ui.html"
