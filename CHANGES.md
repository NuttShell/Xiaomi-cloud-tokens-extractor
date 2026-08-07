# Changes vs. the original

Covers `token_extractor.py`, `Dockerfile`, `run.sh`, `run_docker.sh`, and `.github/workflows/*.yml`. Split into **Bug Fixes** (things that were actually broken) and **New Features / Other Changes** (things that work differently on purpose, not because something was wrong).

## Bug Fixes

### `token_extractor.py` — captcha/QR image display

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

### `run.sh` / `run_docker.sh` / `Dockerfile`

- `host_to_pass=$ha_host || "127.0.0.1"` was dead code — a plain variable assignment always "succeeds" in bash, so the `|| "127.0.0.1"` fallback could never run (and would itself fail with `command not found` if it somehow did). Replaced with a plain `host_to_pass="$ha_host"` in both scripts; the actual fallback already happens a few lines above.
- **Docker**: `-p 31415:31415` was exposed and `--host` was passed to `token_extractor.py`, but `--serve-image` — the flag that actually starts the HTTP server — was never set. Without it, the script fell back to opening the captcha/QR image with a local viewer, which doesn't exist inside a headless container; the port and `--host` were effectively dead. Fixed by baking `--serve-image` into the image's `ENTRYPOINT` in `Dockerfile`, so it's on regardless of how the container is invoked.
- **`run.sh`** (SSH & Web Terminal): same missing-viewer problem as Docker — the terminal is headless too. Added `--serve-image` to the `python3 token_extractor.py` invocation.
- **`run.sh`**: the generated text report (`xiaomi_tokens_*.txt`) is written inside the `token_extractor/` folder, which the script deletes (`rm -rf token_extractor`) immediately after running — the report was created and destroyed in the same run before it could be used. Now copied out to the working directory before cleanup.

### `.github/workflows/build.yml` / `release.yml`

- `release.yml`: `svenstaro/upload-release-action` failed with `Not Found` when the workflow was run manually via `workflow_dispatch` — `github.ref` resolves to a branch (`refs/heads/master`), not a release tag, in that context. The upload steps now run only `if: github.event_name == 'release'`; manual runs still build and upload artifacts, just skip the release-attach step instead of failing.
- `release.yml`: `GITHUB_TOKEN` had no explicit `permissions`, and the repository's default is read-only for new repos — the release-upload step would fail with a 403 in that configuration. Added `permissions: contents: write` at the workflow level.
- `build.yml` / `release.yml`: `actions/checkout@v1` (long unsupported) replaced with `@v4` in every job for consistency — some jobs were already on `@v4`, others were still on `@v1`.

## New Features / Other Changes

*(not bugs — things that behave differently on purpose)*

### `token_extractor.py`

- **No server by default** — captcha/QR images are shown via a temp file opened with `os.startfile()`/the system's default viewer.
- **`--serve-image` flag** — brings back the HTTP server as an opt-in for headless machines, plus `--host` to view the image from another device on the network.
- **Text report** (`xiaomi_tokens_<date_time>.txt`) written next to the script/exe with every device found (NAME/ID/MAC/IP/TOKEN/MODEL/BLE KEY) — no need to scroll the console or pass `--output`/JSON.
- The report includes a login line (only when logging in via email/password; omitted for QR login).
- Report and temp-file paths correctly resolve to the **exe's own folder**, not PyInstaller's temporary extraction directory.
- **Captcha regeneration**: press Enter with no text to get a fresh image, up to 3 images per attempt.
- **Retry on wrong captcha**: up to 3 full submission attempts before giving up, instead of failing on the first wrong character.
- **Session caching** (adapted from upstream PR #197): after a successful login, `userId`/`ssecurity`/`serviceToken`/cookies are saved to `.xiaomi-cloud-session.json`. On the next run, the cache isn't just checked for the right fields — it's actually validated with a live API call, and if it's still good, the entire interactive login (captcha/2FA included) is skipped.
- Custom console window title ("Xiaomi Cloud Tokens Extractor") instead of the default "Python".

### `.github/workflows/build.yml` / `release.yml`

- Removed dead `dev`-branch references from the triggers (the fork only has `master`).
- Added `workflow_dispatch:` to both, so either can be run on demand from the Actions tab without needing a push or a published release — useful for testing a build in isolation.
