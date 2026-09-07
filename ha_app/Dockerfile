FROM python:3-alpine

WORKDIR /usr/src/app

# Supervisor passes this automatically -- it's the `version` field from this
# add-on's config.yaml. Declaring it here and actually USING it below is
# what makes a version bump bust Docker's build-layer cache: without a real
# reference to it in a RUN command, changing config.yaml has zero effect on
# the Dockerfile's instruction text, so Docker keeps reusing the very first
# cached layer forever -- which is exactly the "old script keeps running"
# bug this fixes.
ARG BUILD_VERSION

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
#
# The "echo" of BUILD_VERSION is not decorative -- it's what forces this
# layer (and everything after it) to be rebuilt whenever config.yaml's
# version changes, instead of Docker silently reusing the token_extractor.py
# it happened to download on the very first build.
RUN echo "Add-on version: ${BUILD_VERSION}" && \
    curl -fL -o token_extractor.zip \
        "https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.zip" && \
    unzip token_extractor.zip && \
    mv token_extractor/token_extractor.py token_extractor/requirements.txt . && \
    rm -rf token_extractor.zip token_extractor

RUN pip3 install --no-cache-dir -r requirements.txt

COPY run.sh ./
RUN chmod +x run.sh

CMD [ "./run.sh" ]
