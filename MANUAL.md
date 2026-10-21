# OpenCode CLI - User Manual

**English** | [Español](MANUAL.es.md)

A practical, all-in-one guide to **using OpenCode** once this portable
installer has put it on your machine. Everything here is for **OpenCode V2**.
All key names are the **defaults**; every binding can be changed in
`~/.config/opencode/cli.json` (see [Customizing keybinds](#customizing-keybinds)).

> New here? Start with [Install & first run](#install--first-run), then read
> [The leader key](#the-leader-key-ctrl--x) and
> [Models](#models-show--select) - those two sections solve 90% of "how do I...".

---

## Table of contents

1. [Install & first run](#install--first-run)
2. [Starting OpenCode in Cursor / a terminal](#starting-opencode-in-cursor--a-terminal)
3. [The TUI at a glance](#the-tui-at-a-glance)
4. [The leader key (Ctrl + X)](#the-leader-key-ctrl--x)
5. [Models (show & select)](#models-show--select)
6. [Agents / modes (Build, Plan, ...)](#agents--modes-build-plan-)
7. [Sessions & tabs](#sessions--tabs)
8. [Slash commands](#slash-commands)
9. [Prompting: files, ranges, images, shell](#prompting-files-ranges-images-shell)
10. [Undo, redo and compaction](#undo-redo-and-compaction)
11. [The diff viewer](#the-diff-viewer)
12. [Appearance & navigation](#appearance--navigation)
13. [Editing the prompt (input keys)](#editing-the-prompt-input-keys)
14. [CLI commands (non-interactive)](#cli-commands-non-interactive)
15. [Configuration files](#configuration-files)
16. [Permissions](#permissions)
17. [Customizing keybinds](#customizing-keybinds)
18. [Troubleshooting](#troubleshooting)
19. [Quick reference card](#quick-reference-card)

---

## Install & first run

The installer puts the `opencode` binary in `~/.opencode/bin` and (with your
consent) adds it to the `PATH`. See `README.md` for installation details.

First run:

```bash
cd ~/code/my-project
opencode
```

On first use OpenCode asks you to **connect a model provider** (OpenCode Zen,
Anthropic, OpenAI, Google, a local Ollama/LM Studio server, ...). Pick one and
complete the sign-in. You can also manage credentials from the CLI:

```bash
opencode auth list                 # list saved providers
opencode auth login anthropic      # log in to a provider
opencode auth switch anthropic work
```

> No model provider connected = OpenCode cannot answer. That is the most common
> "it does nothing" cause.

---

## Starting OpenCode in Cursor / a terminal

OpenCode is a **terminal application**, not a Cursor extension. It edits the
files on disk, so any editor open on the same folder (for example Cursor) shows
the changes live.

1. In Cursor open the integrated terminal: `` Ctrl+` ``.
2. Go to your project: `cd path\to\project`.
3. Run `opencode` (add a folder to work elsewhere: `opencode ~/other/project`).

**After installing or changing the `PATH`, restart Cursor completely** (all
windows) so new terminals inherit the updated environment. Opening a new
terminal tab is not always enough.

---

## The TUI at a glance

```
+---------------------------------------------------------------+
|  session transcript (messages, tool calls, diffs)             |
|                                                               |
|  +---------------------------------------------------------+  |
|  | prompt input       > build - your-model            # model
|  +---------------------------------------------------------+  |
+---------------------------------------------------------------+
```

- Type a request and press **Enter** to send it.
- The footer shows the **active agent** (`build`, `plan`, ...) and the
  **active model**.
- While OpenCode is working, **Enter** steers the running session; **Esc**
  interrupts it.

Open the **command palette** for everything available in the current view:

```
Ctrl + P
```

Forgot a shortcut? Toggle **which-key** to discover bindings interactively:

```
Ctrl + Alt + K
```

---

## The leader key (Ctrl + X)

Most "control" actions use a **leader key**: press and release **`Ctrl+X`**,
then press the second key. This is written as **`Ctrl+X` then `M`**.

| Press `Ctrl+X` then... | Action                                    |
| ---------------------- | ----------------------------------------- |
| **M**                  | **List / select models**                  |
| **A**                  | **List / select agents (modes)**          |
| **N**                  | New session                               |
| **L**                  | List sessions                             |
| **W**                  | Close the current session tab             |
| **B**                  | Toggle the sidebar                        |
| **T**                  | Toggle the terminal pane                  |
| **E**                  | Open the external editor for the prompt   |
| **C**                  | Compact the session (free up context)     |
| **G**                  | Show the session timeline                 |
| **S**                  | Show status                               |
| **U**                  | Undo the last message and its work        |
| **R**                  | Redo the undone work                      |
| **X**                  | Export the session to your editor         |
| **Y**                  | Copy the selected message                 |
| **I**                  | View image attachments                    |
| **Q**                  | Exit OpenCode                             |
| **Enter**              | Queue the prompt for later                |

The leader defaults to `Ctrl+X` and can be changed (for example to `Ctrl+Space`)
in `cli.json`.

---

## Models (show & select)

### Why this matters

OpenCode talks to a **provider/model**. If the model is missing, deprecated or
not connected, you get an error instead of an answer. **A model already chosen
for a session overrides the configured default**, so the fix for a broken
session is often to change the *session* model, not the config.

### Change the model for the current session

- **`Ctrl+X` then `M`** - opens the model list, or
- type **`/models`** and press Enter,
- pick an entry (for example `opencode/big-pickle`, `anthropic/claude-sonnet-4-5`).

Inside the model dialog:

| Key     | Action                          |
| ------- | ------------------------------- |
| `Ctrl+A`| Open the provider list          |
| `Ctrl+F`| Favorite / unfavorite a model   |
| Enter   | Select the highlighted model    |

Cycle quickly through recently used models:

| Key        | Action                     |
| ---------- | -------------------------- |
| `F2`       | Next recent model          |
| `Shift+F2` | Previous recent model      |

### Model variants

Some models expose **variants** (reasoning effort / token budgets), selected with
`#variant`, e.g. `openai/gpt-5.2#high`.

- `Ctrl+T` - cycle variants of the current model.

### Set the default model (for new sessions)

Edit `~/.config/opencode/opencode.json` (global) or `./opencode.json` (project):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle"
}
```

Precedence: **session model > project config > global config**. Changing the
config does not rewrite an existing session's model.

### Reference

- List every available model from the CLI: `opencode models`
- Model selector syntax: `provider/model` or `provider/model#variant`

---

## Agents / modes (Build, Plan, ...)

In OpenCode an **agent** is what you might call a "mode": a named assistant with
its own system prompt, model, permissions and tools.

### Switch mode

- **`Shift+Tab`** - cycles to the next agent (fastest way to toggle Build/Plan).
- **`Ctrl+X` then `A`** - opens the agent list, or type **`/agents`**.

### Built-in agents

| Agent        | Mode       | What it does                                                                |
| ------------ | ---------- | --------------------------------------------------------------------------- |
| **Build**    | `primary`  | Default coding agent. Tools allowed by default; makes edits.                |
| **Plan**     | `primary`  | Explores and plans **without editing** normal project files.                |
| **General**  | `subagent` | Research and multi-step work with broad tools; cannot spawn more subagents. |
| **Explore**  | `subagent` | Read/search code or the web without editing files.                          |

Typical flow: use **Plan** to design and **Build** to implement.

- Primary agents run as your main session agent.
- Subagents run in child sessions, launched by the primary agent (the
  `subagent` tool). Example prompt: *"Use the explore subagent to find where
  auth is configured."*

### Set the default agent

```json
{
  "$schema": "https://opencode.ai/config.json",
  "default_agent": "plan"
}
```

If the configured default is unavailable, OpenCode falls back to `build`, then
to the first visible primary-capable agent.

### Custom agents

Create a Markdown file with frontmatter:

```md
---
description: Reviews changes for correctness and regressions
mode: subagent
model: anthropic/claude-sonnet-4-5#high
---
Review the current changes. List findings by severity with file and line refs.
```

Locations: `~/.config/opencode/agents/<name>.md` (global) or
`.opencode/agents/<name>.md` (project). A nested path becomes part of the ID
(`.opencode/agents/team/reviewer.md` -> `team/reviewer`).

---

## Sessions & tabs

A **session** is one conversation with its own history, model and agent.

| Key / command            | Action                                        |
| ------------------------ | --------------------------------------------- |
| `Ctrl+X` then `N`        | New session                                   |
| `Ctrl+X` then `L`        | List sessions                                 |
| `/new`                   | New session (slash command form)              |
| `/sessions`              | Session list                                  |
| `Ctrl+O`                 | Recent sessions and projects together         |
| `Ctrl+R`                 | Rename the current session                    |
| `Ctrl+D`                 | Delete the current session                    |
| `Ctrl+X` then `X`        | Export the session to your editor             |
| `Ctrl+X` then `G`        | Session timeline                              |
| `Ctrl+X` then `C`        | Compact (summarize to save context)           |
| `Esc`                    | Interrupt the running turn                    |
| `Ctrl+B`                 | Background blocking session tools             |

### Tabs

Tabs are on by default.

| Key                   | Action                    |
| --------------------- | ------------------------- |
| `Ctrl+Tab`            | Next open session tab     |
| `Ctrl+Shift+Tab`      | Previous session tab      |
| `Ctrl+1` ... `Ctrl+9` | Jump to tab N             |
| `Ctrl+X` then `W`     | Close current tab         |
| `Ctrl+Shift+T`        | Reopen the last closed tab|

---

## Slash commands

Type `/` at the start of the prompt to list and filter commands.

| Command      | Purpose                                             |
| ------------ | --------------------------------------------------- |
| `/models`    | Choose the model                                    |
| `/agents`    | Choose the agent (mode)                             |
| `/new`       | Start a new session                                 |
| `/sessions`  | List and switch sessions                            |
| `/undo`      | Revert the last message and the work after it       |
| `/redo`      | Restore reverted work                               |
| `/editor`    | Edit the current prompt in your `$EDITOR`           |
| `/btw <q>`   | Ask a side question without adding it to the history|
| `/compact`   | Compact the session                                 |
| `/diff`      | Open the diff viewer                                |
| `/help`      | Show help                                           |

You can also define your own `/commands` (see the project `commands`
configuration).

---

## Prompting: files, ranges, images, shell

### Attach files

Type **`@`** to search and attach a file:

```text
Review @src/auth.ts for error handling problems
Explain @src/auth.ts#20-45
```

### Run a shell command

Type **`!`** at the start of an empty prompt to enter shell mode; the output
stays in the session:

```text
!git status
```

### Side questions

```text
/btw why did the test in step 2 fail?
```

Uses the session context and current model but is **not** added to the
conversation.

### Multiline input

Press **`Shift+Enter`**, **`Ctrl+Enter`**, **`Alt+Enter`** or **`Ctrl+J`** for a
new line inside the prompt.

---

## Undo, redo and compaction

- **`Ctrl+X` then `U`** (or `/undo`) - revert the latest user message and the
  work that followed. The message returns to the composer so you can edit it.
- **`Ctrl+X` then `R`** (or `/redo`) - restore reverted work.
- Sending a new prompt instead accepts the revert and continues from there.
- **`Ctrl+X` then `C`** - compact the session when context grows large.

---

## The diff viewer

Review what the agent changed. Press **`d`** to choose the scope: **All**,
**Committed**, **Uncommitted**, or **Last turn**; select **Base** to change the
comparison branch.

| Key                | Action                                      |
| ------------------ | ------------------------------------------- |
| `j` / `k`          | Move down / up                              |
| `Ctrl+F` / `Ctrl+B`| Page down / up                              |
| `n` / `p`          | Next / previous file (also `Alt+Down/Up`)   |
| `]` / `[`          | Next / previous diff hunk                   |
| `s`                | Toggle single-file patch view               |
| `v`                | Toggle split / unified view                 |
| `b`                | Toggle the file tree                        |
| `d`                | Change the review scope                      |
| `m`                | Mark file reviewed (collapse its patch)     |
| `Esc` / `q`        | Close the diff viewer                       |

Use the mouse to click files or expand folders.

---

## Appearance & navigation

| Key / command        | Action                                   |
| -------------------- | ---------------------------------------- |
| `Ctrl+P`             | Command palette (includes **Settings**)  |
| `Ctrl+X` then `B`    | Toggle sidebar                           |
| `Ctrl+X` then `T`    | Toggle terminal pane                     |
| `Ctrl+X` then `S`    | Show status                              |
| `Ctrl+Alt+K`         | Toggle which-key (discover keybinds)     |
| `Ctrl+C` / `Ctrl+D`  | Exit OpenCode (`Ctrl+X` then `Q` also)   |

Common settings live in **`Ctrl+P` -> Open settings**, or in `cli.json`:
theme, animations, scroll speed, sidebar, thinking visibility, notifications,
mouse capture, and more.

---

## Editing the prompt (input keys)

| Key                                  | Action                          |
| ------------------------------------ | ------------------------------- |
| `Enter`                              | Submit                          |
| `Shift+Enter` / `Ctrl+J` / `Alt+Enter`| New line                       |
| `Ctrl+A` / `Ctrl+E`                  | Start / end of line             |
| `Alt+F` / `Alt+B` (or `Ctrl+Left/Right`)| Word forward / backward      |
| `Ctrl+W`                             | Delete word backward            |
| `Ctrl+U` / `Ctrl+K`                  | Delete to line start / end      |
| `Ctrl+Shift+D`                       | Delete whole line               |
| `Ctrl+-` then `Ctrl+.`               | Undo / redo in the input        |
| `Ctrl+V`                             | Paste                           |
| `Up` / `Down`                        | Prompt history                  |

---

## CLI commands (non-interactive)

Every command supports `--help`.

| Command                          | Purpose                                             |
| -------------------------------- | --------------------------------------------------- |
| `opencode`                       | Open the full-screen TUI                            |
| `opencode <dir>`                 | Open the TUI on another project                     |
| `opencode run "..."`             | Send one prompt, print the reply (scripts/CI)       |
| `opencode mini`                  | Minimal interactive interface                       |
| `opencode session list`          | Manage sessions                                     |
| `opencode auth list`             | Manage providers/credentials                        |
| `opencode models`                | List available models                               |
| `opencode mcp list`              | Manage MCP servers                                  |
| `opencode plugin list`           | Manage plugins                                      |
| `opencode stats`                 | Usage statistics                                    |
| `opencode serve`                 | Start the API / web server                          |
| `opencode service status`        | Control the background server (`start/stop/restart`)|
| `opencode reload`                | Reload configuration without restarting             |
| `opencode debug paths`           | Show global paths (useful for support)              |
| `opencode upgrade`               | Update OpenCode (alias: `opencode update`)          |
| `opencode uninstall`             | Remove OpenCode                                     |

Useful `run` flags:

```bash
opencode run --model anthropic/claude-sonnet-4-5 "Refactor parseToken"
opencode run --agent build "Fix the failing test"
opencode run --continue "Now handle the expired case"
opencode run --format json "List the TODO comments"
opencode run --file src/server.ts --file src/client.ts "Review these for bugs"
```

---

## Configuration files

| File                                    | Scope                                    |
| --------------------------------------- | ---------------------------------------- |
| `~/.config/opencode/opencode.json(c)`   | Global server/project settings           |
| `./opencode.json(c)`                    | Project settings                         |
| `./.opencode/opencode.json(c)`          | Project settings (overrides the above)   |
| `~/.config/opencode/cli.json`           | Terminal (TUI) settings and keybinds     |
| `~/.config/opencode/agents/<name>.md`   | Global custom agents                     |
| `./.opencode/agents/<name>.md`          | Project custom agents                    |

Global server config example:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode/big-pickle",
  "default_agent": "build"
}
```

Locations (for support) can be printed with:

```bash
opencode debug paths
```

---

## Permissions

Agents can be restricted with ordered rules (`allow`, `ask`, `deny`); the last
matching rule wins, so put broad rules first and exceptions after.

```jsonc
{
  "permissions": [
    { "action": "edit",  "resource": "*", "effect": "ask" },
    { "action": "shell", "resource": "git push *", "effect": "deny" }
  ]
}
```

| Action      | Covers                          |
| ----------- | ------------------------------- |
| `shell`     | Shell commands                  |
| `edit`      | Edit / write / patch tools      |
| `read`      | Reading local files             |
| `glob`/`grep`| Local discovery tools          |
| `subagent`  | Child agents                    |
| `webfetch`/`websearch` | Web tools             |
| `skill`     | Skill loading                   |

Set `"session.permissions": "autoaccept"` in `cli.json` to auto-accept requests
(use with care).

---

## Customizing keybinds

Bindings live in `cli.json`. The leader defaults to `ctrl+x`; `<leader>` in
another binding refers to it.

```json
{
  "keybinds": {
    "leader": "ctrl+space",
    "command.palette.show": "ctrl+k",
    "model.list": "<leader>m",
    "agent.list": "<leader>a"
  },
  "leader": { "timeout": 2000 }
}
```

- One key: `"theme.switch": "ctrl+y"`.
- Alternatives: `"app.exit": "ctrl+c,ctrl+d"`.
- Disable: `"help.show": false` or `"none"`.
- Unknown command IDs are rejected.
- `leader.timeout` sets how long to wait after the leader key.

A few useful command IDs: `model.list`, `agent.list`, `session.new`,
`session.list`, `session.compact`, `session.undo`, `session.redo`,
`prompt.editor`, `terminal.toggle`, `session.sidebar.toggle`.

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| **`opencode` is not recognized** | The terminal/Cursor was started before the `PATH` change. **Close Cursor completely and reopen it** (or run `$env:Path += ";$env:USERPROFILE\.opencode\bin"` for the current session). |
| **`Model <name> has been deprecated`** | Change the model with **`Ctrl+X` then `M`** (or `/models`). This is a **per-session** fix; a new session uses the config default. |
| **Config change to `model` seems ignored** | A session that already has a model keeps it. Switch it in the session (`Ctrl+X` `M`) or start a new session (`Ctrl+X` `N`). |
| **OpenCode asks to connect a provider / does nothing** | No provider is connected. Run `opencode auth login <provider>` and pick a model. |
| **TUI looks garbled in the terminal** | Use a terminal with truecolor support. In Cursor, the integrated terminal works; if not, try `opencode mini` for a minimal UI. |
| **I want to see which key does what** | Press `Ctrl+Alt+K` (which-key) or `Ctrl+P` (command palette). |
| **Context is getting too large** | `Ctrl+X` then `C` (compact), or start a new session. |
| **Where is my config?** | `opencode debug paths`. Global config is `~/.config/opencode/`. |

---

## Quick reference card

```
SEND / INTERRUPT
  Enter .................. send
  Shift/Ctrl/Alt+Enter ... new line (also Ctrl+J)
  Esc .................... interrupt the running turn

LEADER = Ctrl+X  (press, release, then the next key)
  Ctrl+X M ............... models (show / select)
  Ctrl+X A ............... agents = modes (Build / Plan / ...)
  Ctrl+X N ............... new session
  Ctrl+X L ............... list sessions
  Ctrl+X B ............... sidebar
  Ctrl+X T ............... terminal pane
  Ctrl+X E ............... external editor
  Ctrl+X C ............... compact
  Ctrl+X U / R ........... undo / redo
  Ctrl+X W ............... close tab
  Ctrl+X Q ............... quit

MODES / MODELS
  Shift+Tab .............. cycle agent (Build <-> Plan)
  Ctrl+T ................. cycle model variant
  F2 / Shift+F2 .......... cycle recent models

SESSIONS / TABS
  Ctrl+O ................. recent sessions & projects
  Ctrl+Tab / Ctrl+Shift+Tab  next / previous tab
  Ctrl+1..9 .............. jump to tab
  Ctrl+Shift+T ........... reopen closed tab

GLOBAL
  Ctrl+P ................. command palette (settings, actions)
  Ctrl+Alt+K ............. which-key (discover keybinds)
  Ctrl+C / Ctrl+D ........ exit

PROMPT
  @ ...................... attach a file (e.g. @src/app.ts#20-45)
  ! ...................... run a shell command
  / ...................... slash commands
```

---

For the installer, updates, offline use and security details, see
[`README.md`](README.md). Official documentation: <https://opencode.ai/v2/docs/>.
