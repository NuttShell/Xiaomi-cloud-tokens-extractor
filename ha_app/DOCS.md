# Xiaomi Cloud Tokens Extractor

## Installation

Follow these steps to get the app (formerly known as add-on) installed on
your system:

1. In Home Assistant, go to **Settings -> Add-ons -> Add-on Store**.
2. Click the **⋮** menu (top right) -> **Repositories**, and add:
   `https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor`
3. Find **Xiaomi Cloud Tokens Extractor** in the store (refresh the page if
   it doesn't show up right away) and open it.
4. Click **Install**. The first install builds the container image on your
   own machine, so it can take a few minutes depending on your hardware --
   this is normal.
5. Once it's installed, open the **Info** tab and click **Start**.

## How to use

1. On the add-on's **Info** tab, click **Start**, then **Open Web UI** (or
   the sidebar icon, if you pinned it). This opens a real terminal, running
   the tool fresh.
2. Choose password or QR-code login, then enter your Xiaomi Home account
   credentials (not your Roborock app credentials).
   - **Password login:** just type your email and password when prompted.
   - **QR-code login:** instead of scanning the code with your phone, you
     can simply open the printed link directly in a browser and finish the
     login there.
3. **If a captcha appears:** the terminal prints a link, normally already
   pointing at your real Home Assistant address, e.g.
   `http://<your-home-assistant-address>:31415` -- open it in a **separate
   browser tab** to see and solve the captcha, then type the answer back
   into the terminal.
   - If the add-on couldn't detect your Home Assistant address on its own,
     that link shows `127.0.0.1` instead -- replace that part with your
     actual Home Assistant address (e.g. `homeassistant.local` or its LAN
     IP) before opening it.
4. Pick which Xiaomi cloud server/region to check from the numbered menu,
   or press `0` to exit without checking any server.
5. Once a check finishes, your devices/tokens print in the terminal and are
   saved as a text report (`xiaomi_tokens_<date>_<time>.txt`) -- also
   reachable at the same `server:port` link from step 3.
6. When the tool exits, if any report(s) already exist, a small menu shows
   up:
   ```
   (L) -- view Latest report
   (A) -- view All report
   (D) -- Delete all report
   ```
   Pick a letter, or just press Enter to skip it and close the terminal.
   Refreshing the Web UI afterwards starts a brand new run.

### Good to know

- This add-on is meant to be started **manually** whenever you need to
  (re-)extract tokens -- it's not meant to be left running in the
  background between uses.
- Report files aren't deleted automatically and pile up across runs; use
  the `(D)` option above, or delete them yourself. They -- and the login
  session cache -- only disappear on their own if the add-on's container is
  rebuilt (Rebuild/reinstall wipes its filesystem; a plain Restart does
  not).
- Your Xiaomi Cloud password is typed directly into the terminal and isn't
  stored by this add-on beyond the session cache
  (`.xiaomi-cloud-session.json`) the tool itself uses to skip the
  login/captcha flow on your next run in the same container session.

## Support

Questions, bug reports, or feature requests -- please open an issue on
GitHub: [NuttShell/Xiaomi-cloud-tokens-extractor](https://github.com/NuttShell/Xiaomi-cloud-tokens-extractor)
