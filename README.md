[![GitHub Latest Release][releases_shield]][latest_release]
[![GitHub All Releases][downloads_total_shield]][releases]<!-- piotrmachowski_support_badges_start -->
[![Ko-Fi][ko_fi_shield]][ko_fi]
[![buycoffee.to][buycoffee_to_shield]][buycoffee_to]
[![PayPal.Me][paypal_me_shield]][paypal_me]
[![Revolut.Me][revolut_me_shield]][revolut_me]
<!-- piotrmachowski_support_badges_end -->

[latest_release]: https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/releases/latest
[releases_shield]: https://img.shields.io/github/release/PiotrMachowski/Xiaomi-cloud-tokens-extractor.svg?style=popout

[releases]: https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/releases
[downloads_total_shield]: https://img.shields.io/github/downloads/PiotrMachowski/Xiaomi-cloud-tokens-extractor/total


# Xiaomi Cloud Tokens Extractor

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
Download and run [token_extractor.exe](https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.exe).

## Linux & Home Assistant (in [SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh))

Execute following command:
```bash
bash <(curl -L https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/raw/master/run.sh)
```

> If installation fails try Docker version

## Docker & Home Assistant (in [SSH & Web Terminal](https://github.com/hassio-addons/addon-ssh))

Execute following command:
```bash
bash <(curl -L https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/raw/master/run_docker.sh)
```

> To run this command in HA you have to disable `protected mode` in addon's settings and restart it

## Manual run in python

Download and unpack archive:
```bash
wget https://github.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/releases/latest/download/token_extractor.zip
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

## Home Assistant additional tools

* [Map extractor](https://github.com/PiotrMachowski/Home-Assistant-custom-components-Xiaomi-Cloud-Map-Extractor) - live map for Xiaomi Vacuums
* [Map card](https://github.com/PiotrMachowski/lovelace-xiaomi-vacuum-map-card) - manual vacuum control from a Lovelace card


<!-- piotrmachowski_support_links_start -->

## Support

If you want to support my work with a donation you can use one of the following platforms:

<table>
  <tr>
    <th>Platform</th>
    <th>Payment methods</th>
    <th>Link</th>
    <th>Comment</th>
  </tr>
  <tr>
    <td>Ko-fi</td>
    <td>
      <li>PayPal</li>
      <li>Credit card</li>
    </td>
    <td>
      <a href='https://ko-fi.com/piotrmachowski' target='_blank'><img height='35px' src='https://storage.ko-fi.com/cdn/kofi6.png?v=6' border='0' alt='Buy Me a Coffee at ko-fi.com' />
    </td>
    <td>
      <li>No fees</li>
      <li>Single or monthly payment</li>
    </td>
  </tr>
  <tr>
    <td>buycoffee.to</td>
    <td>
      <li>BLIK</li>
      <li>Bank transfer</li>
    </td>
    <td>
      <a href="https://buycoffee.to/piotrmachowski" target="_blank"><img src="https://buycoffee.to/btn/buycoffeeto-btn-primary.svg" height="35px" alt="Postaw mi kawę na buycoffee.to"></a>
    </td>
    <td></td>
  </tr>
  <tr>
    <td>PayPal</td>
    <td>
      <li>PayPal</li>
    </td>
    <td>
      <a href="https://paypal.me/PiMachowski" target="_blank"><img src="https://www.paypalobjects.com/webstatic/mktg/logo/pp_cc_mark_37x23.jpg" border="0" alt="PayPal Logo" height="35px" style="height: auto !important;width: auto !important;"></a>
    </td>
    <td>
      <li>No fees</li>
    </td>
  </tr>
  <tr>
    <td>Revolut</td>
    <td>
      <li>Revolut</li>
      <li>Credit Card</li>
    </td>
    <td>
      <a href="https://revolut.me/314ma" target="_blank"><img src="https://assets.revolut.com/assets/favicons/favicon-32x32.png" height="32px" alt="Revolut"></a>
    </td>
    <td>
      <li>No fees</li>
    </td>
  </tr>
</table>

### Powered by
[![PyCharm logo.](https://resources.jetbrains.com/storage/products/company/brand/logos/jetbrains.svg)](https://jb.gg/OpenSourceSupport)


[ko_fi_shield]: https://img.shields.io/static/v1.svg?label=%20&message=Ko-Fi&color=F16061&logo=ko-fi&logoColor=white

[ko_fi]: https://ko-fi.com/piotrmachowski

[buycoffee_to_shield]: https://shields.io/badge/buycoffee.to-white?style=flat&labelColor=white&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAABhmlDQ1BJQ0MgcHJvZmlsZQAAKJF9kT1Iw1AUhU9TpaIVh1YQcchQnayIijhKFYtgobQVWnUweemP0KQhSXFxFFwLDv4sVh1cnHV1cBUEwR8QVxcnRRcp8b6k0CLGC4/3cd49h/fuA4R6malmxzigapaRisfEbG5FDLzChxB6MIZ+iZl6Ir2QgWd93VM31V2UZ3n3/Vm9St5kgE8knmW6YRGvE09vWjrnfeIwK0kK8TnxqEEXJH7kuuzyG+eiwwLPDBuZ1BxxmFgstrHcxqxkqMRTxBFF1ShfyLqscN7irJarrHlP/sJgXltOc53WEOJYRAJJiJBRxQbKsBClXSPFRIrOYx7+QcefJJdMrg0wcsyjAhWS4wf/g9+zNQuTE25SMAZ0vtj2xzAQ2AUaNdv+PrbtxgngfwautJa/UgdmPkmvtbTIEdC3DVxctzR5D7jcAQaedMmQHMlPSygUgPcz+qYcELoFulfduTXPcfoAZGhWSzfAwSEwUqTsNY93d7XP7d+e5vx+AIahcq//o+yoAAAABmJLR0QA/wD/AP+gvaeTAAAACXBIWXMAAAsTAAALEwEAmpwYAAAAB3RJTUUH5wETCy4vFNqLzwAAAVpJREFUOMvd0rFLVXEYxvHPOedKJnKJhrDLuUFREULE7YDCMYj+AydpsCWiaKu29hZxiP4Al4aWwC1EdFI4Q3hqEmkIBI8ZChWXKNLLvS0/Qcza84V3enm/7/s878t/HxGkeTaIGziP+EB918nawu7Dq1d0e1+2J2bepnk2jFEUVVF+qKV51o9neBCaugfge70keoxxUbSWjrQ+4SUyzKZ5NlnDZdzGG7w4DIh+dtZEFntDA98l8S0MYwctNGrYz9WqKJePFLq80g5Sr+EHlnATp+NA+4qLaZ7FfzMrzbMBjGEdq8GrJMZnvAvFC/8wfAwjWMQ8XmMzaW9sdevNRgd3MFhvNpbaG1u/Dk2/hOc4gadVUa7Um425qii/7Z+xH9O4jwW8Cqv24Tru4hyeVEU588cfBMgpPMI9nMFe0BkFzVOYrYqycyQgQJLwTC2cDZCPeF8V5Y7jGb8BUpRicy7OU5MAAAAASUVORK5CYII=

[buycoffee_to]: https://buycoffee.to/piotrmachowski

[buy_me_a_coffee_shield]: https://img.shields.io/static/v1.svg?label=%20&message=Buy%20me%20a%20coffee&color=6f4e37&logo=buy%20me%20a%20coffee&logoColor=white

[buy_me_a_coffee]: https://www.buymeacoffee.com/PiotrMachowski

[paypal_me_shield]: https://img.shields.io/static/v1.svg?label=%20&message=PayPal.Me&logo=paypal

[paypal_me]: https://paypal.me/PiMachowski

[revolut_me_shield]: https://img.shields.io/static/v1.svg?label=%20&message=Revolut&logo=revolut

[revolut_me]: https://revolut.me/314ma
<!-- piotrmachowski_support_links_end -->
