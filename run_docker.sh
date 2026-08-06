#!/usr/bin/env bash
ha_host=$(ha network info --raw-json 2>/dev/null | jq -r '[.data.interfaces[] | select(.ipv4.address[0] != null)][0].ipv4.address[0] | split("/")[0]' 2>/dev/null)
if [ -z "${ha_host}" ]; then
  ha_host="127.0.0.1"
fi
host_to_pass=$ha_host || "127.0.0.1"
set -o errexit  # fail on first error
set -o nounset  # fail on undef var
set -o pipefail # fail on first error in pipe

if [ -f "token_extractor_docker.zip" ]; then
    echo "token_extractor_docker.zip file already exists, please remove it and try again..."
    exit 1
fi

curl --silent --fail --show-error --location --remote-name --remote-header-name\
  https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor_docker.zip
unzip token_extractor_docker.zip
cd token_extractor_docker
docker_image=$(docker build -q -t tokens_extractor .)
docker run --rm -it -p 31415:31415 --name tokens_extractor $docker_image --host $host_to_pass
docker rmi $docker_image
cd ..
rm -rf token_extractor_docker token_extractor_docker.zip
