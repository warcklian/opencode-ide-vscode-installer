# OpenCode IDE Installer (VS Code family)

**Portable**, **adaptive** and **self-updating** installer for the
[OpenCode](https://opencode.ai) CLI, ready to use in the integrated terminal of
**VS Code-based IDEs** (Cursor, VS Code, Windsurf, VSCodium, Trae, ...) on
**Windows, macOS and Linux**.

Copy this folder to any machine, run the installer and you are done. No version
number or artifact URL is hardcoded: it **always resolves the latest available
version live** and follows the packages even if upstream changes the channel,
the npm scope or the CDN.

---

## What it does

1. **Inspects the machine first** (adaptive):
   - platform (OS + architecture + AVX2/baseline + musl),
   - existing OpenCode (managed install and/or another install on `PATH`),
   - available tools (`tar`, `curl`, `git`, `node`, `npm`, `bun`, `pnpm`, `yarn`),
   - whether the install folder is already on the `PATH`.
2. **Resolves the latest version** with a cascade of sources and retries:
   - `https://opencode.ai/update/api/latest/cli/npm` (official endpoint)
   - `https://registry.npmjs.org/@opencode/cli/latest` (npm fallback)
   - `https://api.github.com/repos/anomalyco/opencode/releases/latest` (GitHub fallback)
3. Locates the `@opencode/cli-<platform>` package and reads its **`dist.tarball`**
   and **`dist.integrity`** straight from the npm registry (no hardcoded URLs).
4. **Downloads**, verifies **SHA-512 (base64)** and extracts the binary. If the
   system `tar` is missing it uses a **built-in .NET gzip+tar reader**, so a
   completely bare machine still works.
5. Installs into `~/.opencode/bin`, creates the `opencode2` alias and — **only
   with your consent** — adds it to the **PATH**.
6. Can **self-update** (see below).

All PowerShell is 100% ASCII and compatible with **Windows PowerShell 5.1** (the
one bundled with Windows) and **PowerShell 7+**. All messages and docs are in
**English**.

---

## Requirements

- **Windows**: Windows 10/11 with PowerShell 5.1 (bundled). `tar` is optional
  thanks to the built-in extractor.
- **macOS / Linux**: `curl` and `tar`. Optional `sha512sum` / `shasum` /
  `openssl` for integrity verification (if absent, it is skipped with a warning).
- **Node.js is NOT required.** The downloaded package is already a native binary.

---

## Quick start

### Windows

```powershell
# Double-click install.cmd, or from a terminal:
.\install.cmd
```

`install.cmd` invokes PowerShell with `-ExecutionPolicy Bypass`, so you do not
need to change the system execution policy.

### macOS / Linux

```bash
chmod +x install.sh        # first time only
./install.sh
```

When it finishes, open the **Cursor** integrated terminal (or any terminal) and run:

```bash
opencode
```

---

## Manual

New to OpenCode? Read **[`MANUAL.md`](MANUAL.md)** (English) or
**[`MANUAL.es.md`](MANUAL.es.md)** (Español) - a full user manual with the
keyboard shortcuts (leader key `Ctrl+X`, models, agents/modes such as Build and
Plan, sessions, the diff viewer), the slash commands, the `opencode` CLI
commands, configuration files, permissions and a troubleshooting section.

Quick taste:

| Keys / command        | Action                                              |
| --------------------- | --------------------------------------------------- |
| `Ctrl+X` then `M`     | List / select **models**                            |
| `Shift+Tab`           | Cycle **agent / mode** (Build, Plan, ...)           |
| `Ctrl+X` then `A`     | List agents (modes)                                 |
| `Ctrl+X` then `N`     | New session                                         |
| `Ctrl+P`              | Command palette (settings, all actions)             |
| `Ctrl+Alt+K`          | Which-key: discover every keybind                   |
| `opencode run "..."`  | Non-interactive one-shot prompt                     |

### Local Ollama models

If [Ollama](https://ollama.com) is installed, **`install` registers it
automatically** (provider block in `~/.config/opencode/opencode.json`). Skip
with `-NoOllama` / `--no-ollama`. You can also run setup alone anytime:

```bash
# pull at least one model so the picker is not empty
ollama pull qwen2.5-coder:7b

# optional manual re-sync
.\setup-ollama.cmd      # Windows
./setup-ollama.sh       # macOS / Linux
```

Then `opencode` → **`Ctrl+X` then `M`** → pick `ollama/...`. Details:
[MANUAL.md](MANUAL.md#local-ollama-models) /
[MANUAL.es.md](MANUAL.es.md#modelos-locales-de-ollama).

---

## Adaptive behavior

The installer never assumes a clean machine. Before installing it prints a
report like:

```
System check
  Platform            : windows / x64  -> target windows-x64
  PowerShell          : 5.1.26100.9444
  Extraction method   : tar
  tar                 : C:\WINDOWS\system32\tar.exe
  node                : (not found)
  npm                 : (not found)
  OpenCode (managed)  : not installed
  OpenCode (on PATH)  : not found
  Install dir on PATH : no
```

Then:

- If OpenCode is **already up to date**, it does not reinstall.
- If another OpenCode **outside this folder** (for example installed with npm)
  is already current, it avoids creating a duplicate.
- If the install folder is **not on the PATH**, it **asks** whether to add it:

  ```
  Add OpenCode to your user PATH (C:\Users\you\.opencode\bin)? [Y/n]
  ```

  - Interactive: press Enter (yes) or `n` (no).
  - Non-interactive: pass `-Yes` / `--yes` to accept, or `-NoPath` / `--no-path`
    to refuse. Without either flag, the safe default is **not** to modify the PATH.

---

## Usage

### Windows (`install.ps1` / `install.cmd`)

```powershell
.\install.ps1                          # install/update to the latest
.\install.ps1 -Yes                     # non-interactive; also adds to PATH
.\install.ps1 -Check -Json            # check only (exit 10 = update available)
.\install.ps1 -Update                  # update only if a newer version exists
.\install.ps1 -DryRun -Json           # show the plan without installing
.\install.ps1 -Version 2.0.26         # pin a specific version
.\install.ps1 -InstallDir C:\tools\opencode
.\install.ps1 -Offline                 # install only from the local cache
.\install.ps1 -Force                   # reinstall
.\install.ps1 -NoPath                  # never modify the PATH
.\install.ps1 -Method built-in         # force the built-in extractor
```

### macOS / Linux (`install.sh`)

```bash
./install.sh --version 2.0.26
./install.sh --check
./install.sh --update
./install.sh --dry-run
./install.sh --offline
./install.sh --yes                        # non-interactive; also adds to PATH
./install.sh --install-dir "$HOME/tools/opencode" --no-path
```

### Uninstall

```powershell
# Windows: does not remove OpenCode sessions or user configuration
.\uninstall.ps1 -Purge -RemovePath
```
```bash
# macOS / Linux
./uninstall.sh --purge --remove-path
```

---

## Self-updating

There are **two** levels of self-update.

### 1. OpenCode (the important one)

Every time you run `install.ps1` / `install.sh` (or `update.ps1` / `update.sh`),
the **latest version is resolved live again** and installed if it is newer. If
upstream changes the URL, the CDN or the package name, the installer follows it
because it reads the data from the npm registry.

To make it automatic you can schedule it:

- **Windows (Task Scheduler)**: a daily task running
  `powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\opencode-ide-vscode-installer\update.ps1" -NoPath`
- **macOS / Linux (cron)**:
  `0 9 * * * /path/to/opencode-ide-vscode-installer/update.sh --no-path`

You can also use the native `opencode upgrade` command, since it installs into
`~/.opencode/bin`, the standard OpenCode location.

### 2. The toolkit itself (optional, once you upload it to GitHub)

This folder can also update itself from a repository:

1. The folder is published at `https://github.com/warcklian/opencode-ide-vscode-installer`.
2. Edit `config/settings.json`:

   ```json
   "selfUpdate": {
     "enabled": true,
     "manifestUrl": "https://raw.githubusercontent.com/warcklian/opencode-ide-vscode-installer/main/version.json",
     "repo": "https://github.com/warcklian/opencode-ide-vscode-installer",
     "ref": "main"
   }
   ```

3. Check or apply:

   ```powershell
   .\update-toolkit.ps1 -Check     # exit 10 if a new version exists
   .\update-toolkit.ps1 -Apply     # download and overlay files
   ```

`update-toolkit.ps1` **never** overwrites `config/settings.json` or the cache.
When you publish a new version, bump the number in `version.json`.

---

## Offline installation (copy the folder to a machine without a network)

1. On a networked machine, run the installer once. The package is cached in
   `%LOCALAPPDATA%\opencode-ide-vscode-installer\cache` (Windows) or
   `~/.cache/opencode-ide-vscode-installer` (macOS/Linux).
2. Copy **that cache folder too** to the target machine (same user-relative
   location), or pass `-CacheDir <path>` / `--cache-dir <path>` pointing to the
   copied cache.
3. On the target machine run the installer with `-Offline` / `--offline`.

---

## Integrity and security

- The **SHA-512** of the tarball is verified against the `dist.integrity`
  published by npm before extracting. If it does not match, it is discarded and
  the download is retried / aborted.
- Downloads use **HTTPS** with TLS 1.2+ and retries with exponential backoff.
- The installer **never** runs remote install scripts or `postinstall`: it
  downloads the tarball and extracts the binary directly.
- `config/settings.json` can override any source URL if you need a corporate
  mirror, without touching the code.

---

## Structure

```
opencode-ide-vscode-installer/
├── install.ps1 / install.cmd        # Windows installer
├── update.ps1 / update.cmd          # Windows updater
├── uninstall.ps1 / uninstall.cmd    # Windows uninstaller
├── update-toolkit.ps1               # self-update of this folder (GitHub)
├── install.sh / update.sh / uninstall.sh   # macOS / Linux
├── lib/OpenCodeInstaller.psm1       # reusable core (resolution, download, integrity, extraction)
├── config/settings.json             # source URLs, pinned version, toolkit self-update
├── version.json                     # version of the toolkit itself
├── MANUAL.md                        # user manual: shortcuts, modes, models, CLI
├── MANUAL.es.md                     # same manual in Spanish
├── LICENSE
└── README.md
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Could not resolve the latest version` | No network or proxy. Check `config/settings.json` or use `-Offline` with a warm cache. |
| `No package available for target ...` | Very rare: the target is miscomputed (architecture). Open an issue with your `-DryRun -Json` output. |
| The `opencode` command is not found | Close and reopen the terminal/Cursor so the PATH is reloaded. |
| PATH was not modified | You declined the prompt. Re-run with `-Yes` / `--yes`, or add the folder manually. |
| `tar` not found (Windows) | Not a problem: the installer falls back to its built-in extractor. |
| Odd characters in the console | The PowerShell scripts are intentionally ASCII; non-English text is avoided in code paths. |

---

## License

MIT. See `LICENSE`.
