FROM python:3-alpine

WORKDIR /usr/src/app

# build-base: needed to build pycryptodome/Pillow from source on Alpine (musl)
# ttyd: serves a real, writable terminal over HTTP -- this is what lets the
#       existing, unmodified interactive script run inside the HA ingress UI
#       instead of needing a rewrite into a web app.
# curl/unzip: to fetch the released token_extractor.py below.
RUN apk add --no-cache build-base ttyd curl unzip bash jq

# Always build against the latest published release of the fork, so this
# add-on never drifts out of sync with token_extractor.py -- same
# philosophy already used by run.sh/run_docker.sh. This add-on's own
# `version` in config.yaml tracks changes to *this Dockerfile/run.sh*,
# not the script itself -- rebuilding the add-on always pulls whatever is
# currently the latest GitHub release.
RUN curl -fL -o token_extractor.zip \
        "https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.zip?v=cvvbfg" && \
    unzip token_extractor.zip && \
    mv token_extractor/token_extractor.py token_extractor/requirements.txt . && \
    rm -rf token_extractor.zip token_extractor

RUN pip3 install --no-cache-dir -r requirements.txt

COPY run.sh ./
RUN chmod +x run.sh

CMD [ "./run.sh" ]
