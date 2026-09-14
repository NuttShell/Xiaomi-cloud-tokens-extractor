#!/usr/bin/env bash

ha_host=$(ha network info --raw-json 2>/dev/null | jq -r '[.data.interfaces[] | select(.ipv4.address[0] != null)][0].ipv4.address[0] | split("/")[0]' 2>/dev/null)
if [ -z "${ha_host}" ]; then
  ha_host="127.0.0.1"
fi
host_to_pass="$ha_host"

ZIP_NAME="token_extractor_docker.zip"
BUILD_DIR="token_extractor_docker"
CONTAINER_NAME="tokens_extractor"
APP_DIR="/usr/src/app"  # matches WORKDIR in the Dockerfile
SESSION_CACHE=".xiaomi-cloud-session.json"

# A previous run may have left its session cache sitting here -- the
# container itself never survives a run (see the docker cp steps below),
# so this is what carries the "skip login next time" benefit across runs.
KEEP_SESSION=""
[ -f "$SESSION_CACHE" ] && KEEP_SESSION="$SESSION_CACHE"

# Always do a clean, fresh build: wipe any leftover zip/build folder from
# an interrupted previous run, and remove any stray container that didn't
# get cleaned up properly (e.g. the script was killed mid-run).
rm -rf "$ZIP_NAME" "$BUILD_DIR"
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

set -o errexit  # fail on first error
set -o nounset  # fail on undef var
set -o pipefail # fail on first error in pipe

curl --silent --fail --show-error --location --remote-name --remote-header-name \
  "https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/${ZIP_NAME}"
unzip "$ZIP_NAME"
cd "$BUILD_DIR"

# DOCKER_BUILDKIT=1 opts into BuildKit for this one `docker build` call
# without depending on the separate buildx CLI plugin being installed --
# this is what silences the "legacy builder is deprecated" warning.
docker_image=$(DOCKER_BUILDKIT=1 docker build -q -t tokens_extractor .)

# Create (but don't start) first, so a previously preserved session cache
# can be injected before the container's first login check runs.
# `docker run --rm -it ...` gives no such chance -- and --rm would also
# destroy the container's whole filesystem (cache + report included) the
# instant it exits, before anything could be copied back out.
docker create -it --name "$CONTAINER_NAME" -p 31415:31415 "$docker_image" --host "$host_to_pass" >/dev/null

if [ -n "$KEEP_SESSION" ]; then
    docker cp "../$KEEP_SESSION" "$CONTAINER_NAME:$APP_DIR/$SESSION_CACHE"
fi

docker start -ai "$CONTAINER_NAME"

# Pull the session cache (possibly refreshed by this run) and any
# report(s) back out before the container is removed -- this is the only
# chance, since nothing here relies on --rm.
TMP_OUT=$(mktemp -d)
docker cp "$CONTAINER_NAME:$APP_DIR/." "$TMP_OUT/" 2>/dev/null || true
[ -f "$TMP_OUT/$SESSION_CACHE" ] && mv "$TMP_OUT/$SESSION_CACHE" ..
shopt -s nullglob
for report in "$TMP_OUT"/xiaomi_tokens_*.txt; do
    mv "$report" ..
done
shopt -u nullglob
rm -rf "$TMP_OUT"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker rmi "$docker_image" >/dev/null 2>&1 || true

cd ..
rm -rf "$BUILD_DIR" "$ZIP_NAME"

# View/delete accumulated reports -- same menu as the other run scripts.
# Nothing is deleted automatically otherwise.
shopt -s nullglob
reports=(xiaomi_tokens_*.txt)
shopt -u nullglob

if [ ${#reports[@]} -gt 0 ]; then
    echo
    echo "Report(s) found:"
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
