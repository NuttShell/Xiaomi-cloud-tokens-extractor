#!/usr/bin/env bash

ha_host=$(ha network info --raw-json 2>/dev/null | jq -r '[.data.interfaces[] | select(.ipv4.address[0] != null)][0].ipv4.address[0] | split("/")[0]' 2>/dev/null)
if [ -z "${ha_host}" ]; then
  ha_host="127.0.0.1"
fi
host_to_pass="$ha_host"

INSTALL_DIR="token_extractor"
TMP_KEEP=""

# Always do a clean, fresh install -- but preserve the session cache and
# any reports first, so a stale/broken previous install can never be the
# reason something doesn't work, while still not losing what's meant to
# persist between runs.
if [ -d "$INSTALL_DIR" ]; then
    TMP_KEEP=$(mktemp -d)
    [ -f "$INSTALL_DIR/.xiaomi-cloud-session.json" ] && mv "$INSTALL_DIR/.xiaomi-cloud-session.json" "$TMP_KEEP/"
    shopt -s nullglob
    for report in "$INSTALL_DIR"/xiaomi_tokens_*.txt; do mv "$report" "$TMP_KEEP/"; done
    shopt -u nullglob
    rm -rf "$INSTALL_DIR"
fi

set -o errexit  # fail on first error
set -o nounset  # fail on undef var
set -o pipefail # fail on first error in pipe

if [ -f "$INSTALL_DIR.zip" ]; then
    rm -f "$INSTALL_DIR.zip"
fi
curl --silent --fail --show-error --location --remote-name --remote-header-name \
  "https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/${INSTALL_DIR}.zip"
unzip "$INSTALL_DIR.zip"
rm -f "$INSTALL_DIR.zip"

cd "$INSTALL_DIR"

# Move the preserved session cache/reports back into place.
if [ -n "$TMP_KEEP" ]; then
    [ -f "$TMP_KEEP/.xiaomi-cloud-session.json" ] && mv "$TMP_KEEP/.xiaomi-cloud-session.json" .
    shopt -s nullglob
    for f in "$TMP_KEEP"/xiaomi_tokens_*.txt; do mv "$f" .; done
    shopt -u nullglob
    rmdir "$TMP_KEEP" 2>/dev/null || true
fi

clear

python3 -m venv .venv
source .venv/bin/activate
pip3 install --quiet -r requirements.txt
python3 token_extractor.py --serve-image --host "$host_to_pass"
deactivate

cd ..

# View/delete accumulated reports -- same menu as the Home Assistant
# add-on's run.sh. Nothing is deleted automatically otherwise.
shopt -s nullglob
reports=("$INSTALL_DIR"/xiaomi_tokens_*.txt)
shopt -u nullglob

if [ ${#reports[@]} -gt 0 ]; then
    echo
    echo "Report(s) found in ./$INSTALL_DIR:"
    printf "  %s\n" "${reports[@]}"
    echo
    echo "-------------------------------------------------------------"
    echo "  (L) -- view Latest report"
    echo "  (V) -- view All reports"
    echo "  (D) -- Delete all reports"
    echo "-------------------------------------------------------------"
    read -r -p " View [L]atest, [V]iew all, [D]elete all, or press Enter to exit: " CHOICE
    case "${CHOICE^^}" in
        L)
            latest=$(ls -t "${reports[@]}" | head -1)
            echo
            echo
            echo "---- $latest ----"
            cat "$latest"
            echo "---- end ----"
            echo
            ;;
        V)
            echo
            echo
            echo "--- Begin ---"
            cat "${reports[@]}"
            echo "---- end ----"
            echo
            ;;
        D)
            rm -f "${reports[@]}"
            echo
            echo
            echo "Deleted all xiaomi_tokens."
            echo
            ;;
    esac
fi
