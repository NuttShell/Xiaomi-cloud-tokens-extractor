# Xiaomi Cloud Tokens Extractor

_This is a fork of [PiotrMachowski/Xiaomi-cloud-tokens-extractor](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor) with additional fixes and features — see [Changes vs. the original](#changes-vs-the-original-token_extractorpy) below. All credit for the original tool goes to Piotr Machowski._

This tool retrieves tokens for all devices connected to Xiaomi cloud and encryption keys for BLE devices.

It supports two ways of authentication:
- username (e-mail/Xiaomi Cloud account ID) & password
- QR code

After logging in you have to select a Xiaomi's server region (`cn` - China, `de` - Germany etc.). Leave it empty to check all available

In return all of your devices connected to account will be listed, together with their name and IP address.

# Changes vs. the original `token_extractor.py`

## Bugs fixed

**Captcha/QR image display**

- On Windows, `HTTPServer` defaults to `SO_REUSEADDR`, which let a second process silently bind the same port (31415) while an earlier, still-running instance was still listening — the OS would then route requests unpredictably between the old and new server. This was the cause of the "captcha from a previous run" symptom, hangs, and a `ConnectionAbortedError` traceback.
- Single-threaded `HTTPServer` replaced with `ThreadingHTTPServer`, so one stalled connection can't block others.
- Server responses were missing `Content-Type`/`Content-Length`/`Cache-Control` headers.
- A client disconnecting mid-transfer (closed tab, cancelled load) raised an unhandled traceback; now caught and logged quietly.
- The server was never explicitly shut down — added `stop_image_server()` + `atexit` cleanup.
- **The main "Python" console bug**: Pillow's `Image.show()` on Windows shells out through `cmd.exe` (`start "Pillow" /WAIT "<file>" && ping -n 4 127.0.0.1 >NUL && del /f "<file>"`). In the PyInstaller-built exe specifically, that chain ended up invoking the bare `python` command, which resolved to the Windows App Execution Alias stub ("Python was not found...") and printed its message straight into the console. Fixed by opening the image with a direct `os.startfile()` call instead.
- Along the way, found and removed a duplicate `colorama.init()` call (double-wrapping stdout) — a likely contributor to similar glitches specifically under PyInstaller.
- Temporary captcha/QR image files (`delete=False`) were never cleaned up — added `atexit`-based removal.
- The console window's default title (bare "Python", since the embeddable `python.exe` doesn't set one) is now set explicitly.
- A single wrong captcha character failed the entire login, requiring a full restart.
- An unreadable captcha image couldn't be regenerated without restarting the script.

## New features

- **No server by default** — captcha/QR images are shown via a temp file opened with `os.startfile()`/the system's default viewer.
- **`--serve-image` flag** — brings back the HTTP server as an opt-in for headless machines, plus `--host` to view the image from another device on the network.
- **Text report** (`xiaomi_tokens_<date_time>.txt`) written next to the script/exe with every device found (NAME/ID/MAC/IP/TOKEN/MODEL/BLE KEY) — no need to scroll the console or pass `--output`/JSON.
- The report includes a login line (only when logging in via email/password; omitted for QR login).
- Report and temp-file paths correctly resolve to the **exe's own folder**, not PyInstaller's temporary extraction directory.
- **Captcha regeneration**: press Enter with no text to get a fresh image, up to 3 images per attempt.
- **Retry on wrong captcha**: up to 3 full submission attempts before giving up, instead of failing on the first wrong character.
- **Session caching** (adapted from upstream PR #197): after a successful login, `userId`/`ssecurity`/`serviceToken`/cookies are saved to `.xiaomi-cloud-session.json`. On the next run, the cache isn't just checked for the right fields — it's actually validated with a live API call, and if it's still good, the entire interactive login (captcha/2FA included) is skipped.
- Custom console window title ("Xiaomi Cloud Tokens Extractor") instead of the default "Python".

## Windows


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

## Troubleshooting

If you have problems with using this tool try following solutions:
- Make yourself sure that you provide correct credentials (_e.g. not ones from Roborock app!_)
- Remove Cloudflare DNS
- Disable network ad blockers (AdGuard, PiHole, etc.) and restrictions (UniFi Country Restriction etc.)
- Check SPAM folders for 2FA e-mail
- Use QR code authentication instead of username & password
- Just wait - there is a [limit of 3/5 (depending on region) 2FA requests per day](https://account.xiaomi.com/helpcenter/faq/en_US/02.faqs/05.sms-and-email-verification-code/faq-3)
