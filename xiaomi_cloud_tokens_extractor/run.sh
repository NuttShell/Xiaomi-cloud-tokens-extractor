#!/usr/bin/env bash
set -euo pipefail

cd /usr/src/app

# Ask the Supervisor for this host's real LAN IP -- the container's own
# internal address wouldn't be reachable from your browser, but this is
# the same address Home Assistant itself is reachable at, since port
# 31415 is published straight to the host (see config.yaml).
HA_HOST=""
if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    HA_HOST=$(curl -sf -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                    http://supervisor/network/info 2>/dev/null \
              | jq -r '([.data.interfaces[]? | select(.ipv4.address[0] != null)] | .[0].ipv4.address[0]) // empty' 2>/dev/null \
              | cut -d/ -f1) || true
fi

ARGS=(--serve-image)
if [ -n "$HA_HOST" ]; then
    echo "Detected Home Assistant address: $HA_HOST"
    ARGS+=(--host "$HA_HOST")
else
    echo "Could not auto-detect the Home Assistant address -- the captcha/QR URL will show"
    echo "127.0.0.1; open http://<your-home-assistant-address>:31415 yourself instead."
fi

# -W (--writable): without this, ttyd serves a READ-ONLY terminal -- you'd
#   see the output but couldn't type your username/password/captcha at all.
# -p 7681: matches ingress_port in config.yaml.
#
# After token_extractor.py exits, this drops into a real bash shell in the
# same directory instead of closing the session -- that's how you get to
# the saved xiaomi_tokens_*.txt report (and .xiaomi-cloud-session.json)
# afterwards: `cat`/`less` to view, `rm` to delete. Type `exit` to close.
# Nothing here is deleted automatically -- these files only disappear if
# you remove them yourself, or if the add-on's container is rebuilt
# (Rebuild/reinstall wipes its writable filesystem; a plain Restart does
# not).
exec ttyd -p 7681 -W bash -c '
    python3 token_extractor.py "$@"
    echo
    echo "-------------------------------------------------------------"
    echo "Script finished. Files in this directory:"
    ls -la
    echo
    echo "  cat xiaomi_tokens_*.txt   -- view the report"
    echo "  rm xiaomi_tokens_*.txt    -- delete it"
    echo "  exit                      -- close this session"
    echo "-------------------------------------------------------------"
    exec bash
' _ "${ARGS[@]}"
