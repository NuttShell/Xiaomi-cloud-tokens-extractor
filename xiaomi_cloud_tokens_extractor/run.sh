#!/usr/bin/env bash
set -euo pipefail

cd /usr/src/app

# -W (--writable): without this, ttyd serves a READ-ONLY terminal -- you'd
#   see the output but couldn't type your username/password/captcha at all.
# -p 7681: matches ingress_port in config.yaml.
# --serve-image: this container has no display, so the captcha/QR code has
#   to go over HTTP (port 31415, mapped in config.yaml) instead of trying
#   to open a local image viewer that doesn't exist here.
exec ttyd -p 7681 -W python3 token_extractor.py --serve-image
