<h2 align="left">
  <a href="https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor">
    <img src="/xiaomi_cloud_tokens_extractor/logo.png" alt="NuttShell - GitHub">
  </a>
</h2>

# Xiaomi Cloud Tokens Extractor

Runs [token_extractor.py](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor)
inside a real, interactive terminal right inside the Home Assistant UI --
no SSH, no separate Docker command to remember.

## Usage

1. Start the add-on (**Info** tab -> **Start**).
2. Click **Open Web UI** (or the sidebar icon, if you pinned it) -- this
   opens a terminal, running the tool fresh.
3. Follow the prompts: choose password or QR login, enter your Xiaomi
   Home credentials (not your Roborock app credentials), pick a server
   region.
4. **If a captcha or QR code appears:** the terminal will print something
   like `Image URL: http://127.0.0.1:31415` -- ignore the `127.0.0.1`
   part and instead open `http://<your-home-assistant-address>:31415` in
   a **separate browser tab** (same address you use to reach Home
   Assistant itself, e.g. `homeassistant.local` or its LAN IP). Solve the
   captcha or scan the QR code there, then type the answer back in the
   terminal tab.
5. Once logged in, your devices/tokens print in the terminal and also get
   saved as a text report (`xiaomi_tokens_<date>_<time>.txt`) inside the
   add-on's own container filesystem for that session.

## Notes

- The terminal re-runs the tool from scratch every time you open the Web
  UI fresh (refreshing the page starts a new run). That's normal.
- This add-on is meant to be started **manually** when you need to
  (re-)extract tokens, not left running continuously -- there's nothing
  to run in the background between uses.
- Your Xiaomi Cloud password is typed directly into the terminal and is
  not stored by this add-on beyond the session cache
  (`.xiaomi-cloud-session.json`) the tool itself already uses to avoid
  repeating the login/captcha flow on the very next run in the same
  container session.
