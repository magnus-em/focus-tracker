#!/bin/bash
# deploy.sh — safe install that preserves Focus session data
# Usage: ./deploy.sh (run from repo root after ./build.sh)
set -e

SESSIONS_FILE="$HOME/Library/Application Support/Focus/sessions.json"
BACKUP="/tmp/focus_sessions_backup_$(date +%Y%m%d_%H%M%S).json"

echo "── Pre-install ──────────────────────────────"

if [ -f "$SESSIONS_FILE" ]; then
    SESSION_COUNT=$(python3 -c "
import json
try:
    d = json.load(open('$SESSIONS_FILE'))
    print(len(d) if isinstance(d, list) else len(d.get('sessions', [])))
except Exception as e:
    print('?')
")
    cp "$SESSIONS_FILE" "$BACKUP"
    echo "Sessions: $SESSION_COUNT  (backup → $BACKUP)"
else
    echo "No sessions file yet"
    SESSION_COUNT=0
fi

echo "── Quitting ──────────────────────────────────"
if pgrep -x Focus > /dev/null 2>&1; then
    # SIGTERM lets the app run willTerminateNotification (saves checkpoint + unblocks sites)
    pkill -TERM -x Focus
    for i in $(seq 1 20); do
        sleep 0.2
        pgrep -x Focus > /dev/null 2>&1 || break
    done
    if pgrep -x Focus > /dev/null 2>&1; then
        echo "Still running — force killing"
        pkill -9 -x Focus
        sleep 0.3
    fi
    echo "Quit."
else
    echo "Not running."
fi

echo "── Installing ───────────────────────────────"
cp -r Focus.app /Applications/

echo "── Verifying ────────────────────────────────"
if [ -f "$SESSIONS_FILE" ]; then
    SESSION_COUNT_AFTER=$(python3 -c "
import json
try:
    d = json.load(open('$SESSIONS_FILE'))
    print(len(d) if isinstance(d, list) else len(d.get('sessions', [])))
except Exception as e:
    print('?')
")
    echo "Sessions after: $SESSION_COUNT_AFTER"
    if [ "$SESSION_COUNT_AFTER" = "?" ] && [ "$SESSION_COUNT" != "0" ]; then
        echo "WARNING: sessions.json unreadable — restoring backup"
        cp "$BACKUP" "$SESSIONS_FILE"
    fi
else
    echo "No sessions file (expected if first run)"
fi

echo "── Launching ────────────────────────────────"
open /Applications/Focus.app
echo "Done."
