#!/usr/bin/env bash
set -euo pipefail

cd /usr/src/app

# --- Detect this host's real LAN IP via the Supervisor API -------------
# The container's own internal address wouldn't be reachable from your
# browser, but this is the same address Home Assistant itself is
# reachable at, since port 31415 is published straight to the host (see
# config.yaml). Prints diagnostics on failure instead of failing silently,
# since this has been unreliable and needs real data to debug further.
HA_HOST=""
if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    NET_INFO=$(curl -sf -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                     http://supervisor/network/info 2>&1) || NET_INFO=""
    if [ -n "$NET_INFO" ]; then
        HA_HOST=$(printf '%s' "$NET_INFO" \
                  | jq -r '([.data.interfaces[]? | select(.ipv4.address[0] != null)] | .[0].ipv4.address[0]) // empty' 2>/dev/null \
                  | cut -d/ -f1) || true
    fi
    if [ -z "$HA_HOST" ]; then
        echo "[debug] Supervisor API call did not yield a usable address."
        echo "[debug] Raw response (first 500 chars):"
        printf '%s' "$NET_INFO" | head -c 500
        echo
    fi
else
    echo "[debug] SUPERVISOR_TOKEN is not set in this container's environment at all."
fi

ARGS=(--serve-image)
if [ -n "$HA_HOST" ]; then
    echo "Detected Home Assistant address: $HA_HOST"
    ARGS+=(--host "$HA_HOST")
else
    echo "Could not auto-detect the Home Assistant address -- the captcha/QR URL will show"
    echo "127.0.0.1; open http://<your-home-assistant-address>:31415 yourself instead."
fi

# --- Terminal session ----------------------------------------------------
# -W (--writable): without this, ttyd serves a READ-ONLY terminal -- you'd
#   see the output but couldn't type your username/password/captcha at all.
# -p 7681: matches ingress_port in config.yaml.
#
# ttyd re-invokes this same command from scratch every time you press
# Enter on its "Press Enter to restart" prompt (an `exec bash` trick to
# stay in a shell after the script exits did not actually keep the
# session open -- ttyd's own restart behavior wins). So instead of
# fighting that, this checks for a leftover report *before* running the
# extractor each time, since that's the point where a fresh invocation is
# guaranteed to happen anyway.
exec ttyd -p 7681 -W bash -c '
    shopt -s nullglob
    reports=(xiaomi_tokens_*.txt)
    shopt -u nullglob
    if [ ${#reports[@]} -gt 0 ]; then
        echo "Existing report(s) found:"
        printf "  %s\n" "${reports[@]}"
        echo
        read -r -p "[V]iew most recent, [D]elete all, or press Enter to run the extractor: " CHOICE
        case "${CHOICE^^}" in
            V)
                latest=$(ls -t xiaomi_tokens_*.txt | head -1)
                echo "--- $latest ---"
                cat "$latest"
                echo "--- end ---"
                echo
                read -r -p "Press Enter to continue to the extractor: " _
                ;;
            D)
                rm -f xiaomi_tokens_*.txt
                echo "Deleted."
                ;;
        esac
    fi
    python3 token_extractor.py "$@"
' _ "${ARGS[@]}"
