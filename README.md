[![GitHub release](https://img.shields.io/github/v/release/NuttShell/Xiaomi-cloud-tokens-extractor)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest)
[![GitHub Release Date](https://img.shields.io/github/release-date/NuttShell/Xiaomi-cloud-tokens-extractor)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/NuttShell/Xiaomi-cloud-tokens-extractor/total)](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases)

<h1 align="center">
  <a href="https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor">
    <img src="./ha_app/logo.png" alt="NuttShell - GitHub">
  </a>
</h1>

# Xiaomi Cloud Tokens Extractor

_This is a fork of [PiotrMachowski/Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) with additional fixes and features — see [Changes vs. the original](#changes-vs-the-original-token_extractorpy) below. All credit for the original tool goes to Piotr Machowski._
#### Changes vs. the original `token_extractor.py` - full list at [`CHANGES.md`](./CHANGES.md).


This tool retrieves tokens for all devices connected to Xiaomi cloud and encryption keys for BLE devices.

It supports two ways of authentication:
- username (e-mail/Xiaomi Cloud account ID) & password
- QR code

A successful login is cached, so you won't be asked to log in again on your next run as long as it's still valid -- encrypted on Windows, `chmod 600`-protected on Linux (see the [Linux](#linux) section below for exactly where it's stored there).

After logging in you pick a Xiaomi server region from a numbered list (`cn` - China, `de` - Germany, etc.), or leave it empty/press Enter to check all of them.

In return, all of your devices connected to the account are listed -- name, model, firmware version, ID, MAC, IP address, token, and BLE beacon key where applicable -- and saved to a timestamped report file.

The script can also run fully non-interactively, with credentials, server, and output file passed as command-line flags instead of prompts. Run it with `--help` (or `-h`) to see the full list of options.

## Home Assistant App

1. In Home Assistant, go to **Settings -> App -> Install App**.
2. Click the **⋮** menu (top right) -> **Repositories**, and add:
   `https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor`
3. Find **Xiaomi Cloud Tokens Extractor** in the store (refresh the page if
   it doesn't show up right away) and open it.
4. Click **Install**. The first install builds the container image on your
   own machine, so it can take a few minutes depending on your hardware --
   this is normal.
5. Once it's installed, open the **Info** tab and click **Start**.
 
   or
   
[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FNuttShell%2FXiaomi-cloud-tokens-extractor)
   
 **Settings -> App -> Install App -> Xiaomi Cloud Tokens Extractor -> Install > Start**


## Linux & Home Assistant (in [SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh))

Execute following command:
```bash
bash <(curl -L https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/raw/master/run.sh)
```

## Windows
Download and run [token_extractor.exe](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.exe).

or build token_extractor.exe from token_extractor.py yourself - see  [Windows build tools](make_win/readme.md)

## Linux

### Quick install

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/NuttShell/Xiaomi-cloud-tokens-extractor/master/installTokenExtractorLinux.sh)
```

This installs `token-extractor` system-wide under `/opt/xiaomi-token-extractor/`, with a `token-extractor` command added to `PATH`. The script supports interactive and non-interactive installation, updates, and removal. When run interactively, you can:

- **Install / update to latest** -- installs the latest release, or updates an existing install
- **Install a specific version** -- pin to a given release (e.g. `1.0.5`)
- **Check for updates** -- reports the installed vs. latest version, changes nothing
- **Uninstall** -- removes the binary and the `token-extractor` command, but keeps your cached login session so a reinstall won't ask you to log in again
- **Delete All data** -- uninstall, plus wipe every account's cached Xiaomi login session and saved reports (`~/.xiaomi-token-extractor/`) on this machine

Download first and set execute permissions if you'd rather not pipe straight into `bash`:

```bash
curl -fsSL https://raw.githubusercontent.com/NuttShell/Xiaomi-cloud-tokens-extractor/master/installTokenExtractorLinux.sh -o installTokenExtractorLinux.sh
chmod 755 installTokenExtractorLinux.sh
sudo ./installTokenExtractorLinux.sh
```

Command-line examples:
```bash
sudo ./installTokenExtractorLinux.sh --install              # install the latest release
sudo ./installTokenExtractorLinux.sh --install 1.0.5         # install a specific version
sudo ./installTokenExtractorLinux.sh --update --silent       # update to latest, no prompts
sudo ./installTokenExtractorLinux.sh --check                 # just check whether an update exists
sudo ./installTokenExtractorLinux.sh --remove                # uninstall (keeps cached login)
sudo ./installTokenExtractorLinux.sh --delete-all-data        # uninstall + wipe all cached sessions
```

Run `./installTokenExtractorLinux.sh --help` for the full list of options.

### Without the install script

If you'd rather manage it yourself, the raw binary and both package formats are attached to every [release](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases):

**Raw binary** -- no installation, just download and run:
```bash
curl -fsSL -o token-extractor https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor_linux_amd64
chmod +x token-extractor
./token-extractor --help
```

**.deb** (Debian, Ubuntu, and derivatives):
```bash
curl -fsSL -o token-extractor.deb https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor_linux_amd64.deb
sudo dpkg -i token-extractor.deb
```

**.rpm** (Fedora, RHEL, and derivatives):
```bash
curl -fsSL -o token-extractor.rpm https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor_linux_amd64.rpm
sudo rpm -i token-extractor.rpm
```

> Only amd64 (x86_64) builds are published right now, and they need glibc 2.31 or newer (Debian 11 / Ubuntu 20.04 or newer). Session cache and saved reports live per-user under `~/.xiaomi-token-extractor/`, separate from the install location.

## Manual run in python

Download and unpack archive:
```bash
wget https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.zip
unzip token_extractor.zip
cd token_extractor
```

Install dependencies and run script:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip3 install -r requirements.txt
python3 token_extractor.py
deactivate
```

> Add `--host <LAN IP>` as well if you want to open it from another device on the network.

## Troubleshooting

If you have problems with using this tool try following solutions:
- Make yourself sure that you provide correct credentials (_e.g. not ones from Roborock app!_)
- Remove Cloudflare DNS
- Disable network ad blockers (AdGuard, PiHole, etc.) and restrictions (UniFi Country Restriction etc.)
- Check SPAM folders for 2FA e-mail
- Use QR code authentication instead of username & password
- Just wait - there is a [limit of 3/5 (depending on region) 2FA requests per day](https://account.xiaomi.com/helpcenter/faq/en_US/02.faqs/05.sms-and-email-verification-code/faq-3)
