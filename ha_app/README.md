[![GitHub release](https://img.shields.io/github/v/release/NuttShell/Xiaomi-cloud-tokens-extractor)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest)

<img src="https://raw.githubusercontent.com/NuttShell/Xiaomi-cloud-tokens-extractor/master/ha_app/logo.png" width="200">

# Xiaomi Cloud Tokens Extractor

Runs [token_extractor.py](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor)
inside a real, interactive terminal right inside the Home Assistant UI --
no SSH, no separate Docker command to remember.

## About

Most Xiaomi/Mi Home devices only expose their local API once you know their
per-device **token**, and BLE-based Xiaomi devices need an **encryption key**
on top of that -- both of these live in Xiaomi's cloud, not on the device
itself, and Xiaomi doesn't show them to you anywhere in the app. This add-on
packages [token_extractor.py](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor)
(a fork of Piotr Machowski's original, widely used script) so it runs as a
real, interactive terminal right inside the Home Assistant UI -- no SSH
session, no manually running a Docker container, nothing to install on your
own machine. Log in with your Xiaomi account once, and you get every
device's token (and BLE key, where applicable) printed straight to the
screen and saved to a report you can come back to.

## Features

- **Password or QR-code login** -- log in with your Xiaomi/Mi Home email and
  password, or use the QR-code flow instead. For the QR code, you don't
  need to actually scan anything with your phone: the image is served as a
  plain link, so you can just open it in a browser and complete the login
  there.
- **One-click captcha/QR link** -- if Xiaomi asks for a captcha (or shows
  the QR login image), the add-on detects your Home Assistant instance's
  real address on its own and prints a ready-to-click
  `http://<your-home-assistant-address>:31415` link -- nothing to edit or
  guess at.
- **Session caching** -- once you're logged in, that session is cached for
  as long as the add-on's container is running, so re-running the tool
  doesn't make you log in (or solve a captcha) all over again.
- **Numbered server menu** -- pick which Xiaomi cloud server/region to
  check for devices from a plain numbered list of country names (instead
  of raw server codes), or just press `0` to exit straight away without
  checking any server.
- **Latest report, one link away** -- the most recently generated token
  report is served over that same `server:port` link, so you can pull it
  up from another device without needing the terminal.
- **Built-in report manager** -- once a run finishes, a small menu lets you
  view the latest report, view every report you've collected so far, or
  delete them all -- right there in the terminal, no manual file digging
  required.

