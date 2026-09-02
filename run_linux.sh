#!/usr/bin/env bash
ha_host=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
if [ -z "${ha_host}" ]; then
  ha_host="127.0.0.1"
fi
host_to_pass="$ha_host"
set -o errexit
set -o nounset
set -o pipefail
if [ -f "token_extractor.zip" ]; then
    echo "token_extractor.zip file already exists, please remove it and try again..."
    exit 1
fi
curl --silent --fail --show-error --location --remote-name --remote-header-name \
  https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.zip
unzip token_extractor.zip
cd token_extractor
python3 -m venv .venv && source .venv/bin/activate
pip3 install -r requirements.txt
python3 token_extractor.py --serve-image --host "$host_to_pass"
deactivate
cd ..
rm -rf token_extractor.zip
