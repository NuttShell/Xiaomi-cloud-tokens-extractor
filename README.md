[![GitHub release](https://img.shields.io/github/v/release/NuttShell/Xiaomi-cloud-tokens-extractor)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest)
[![GitHub Release Date](https://img.shields.io/github/release-date/NuttShell/Xiaomi-cloud-tokens-extractor)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/NuttShell/Xiaomi-cloud-tokens-extractor/total)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases)

# Xiaomi Cloud Tokens Extractor

_This is a fork of [PiotrMachowski/Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) with additional fixes and features — see [Changes vs. the original](#changes-vs-the-original-token_extractorpy) below. All credit for the original tool goes to Piotr Machowski._

This tool retrieves tokens for all devices connected to Xiaomi cloud and encryption keys for BLE devices.

It supports two ways of authentication:
- username (e-mail/Xiaomi Cloud account ID) & password
- QR code

After logging in you have to select a Xiaomi's server region (`cn` - China, `de` - Germany etc.). Leave it empty to check all available

In return all of your devices connected to account will be listed, together with their name and IP address.

# Changes vs. the original `token_extractor.py`

Full list at [`CHANGES.md`](./CHANGES.md).

## Windows
Download and run [token_extractor.exe](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.exe).

or build token_extractor.exe from token_extractor.py yourself - see  [Windows build tools](make_win/readme.md)

## Linux & Home Assistant (in [SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh))

Execute following command:
```bash
bash <(curl -L https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/raw/master/run.sh)
```

> If installation fails try Docker version

## Docker & Home Assistant (in [SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh))

Execute following command:
```bash
bash <(curl -L https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/raw/master/run_docker.sh)
```

> To run this command in HA you have to disable `protected mode` in addon's settings and restart it

## Manual run in python

Download and unpack archive:
```bash
wget https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.zip
unzip token_extractor.zip
cd token_extractor
```

Install dependencies and run script:
```bash
pip3 install -r requirements.txt
python3 token_extractor.py
```

> On a headless machine (no display/image viewer available) add `--serve-image` to view the captcha/QR code over HTTP instead: `python3 token_extractor.py --serve-image`. Add `--host <LAN IP>` as well if you want to open it from another device on the network.

## Troubleshooting

If you have problems with using this tool try following solutions:
- Make yourself sure that you provide correct credentials (_e.g. not ones from Roborock app!_)
- Remove Cloudflare DNS
- Disable network ad blockers (AdGuard, PiHole, etc.) and restrictions (UniFi Country Restriction etc.)
- Check SPAM folders for 2FA e-mail
- Use QR code authentication instead of username & password
- Just wait - there is a [limit of 3/5 (depending on region) 2FA requests per day](https://account.xiaomi.com/helpcenter/faq/en_US/02.faqs/05.sms-and-email-verification-code/faq-3)
