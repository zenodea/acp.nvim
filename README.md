# acp.nvim

Zed-style agent threads for Neovim, powered by the Claude Code CLI.

Each **thread** owns a full workspace: its own tab page, its own window layout,
optionally its own **git worktree** — and a chat panel talking to its own
Claude Code session. A sidebar shows every thread with a live status, so you
can run several agents in parallel and see at a glance which one is working,
which one is waiting on you, and which one is done.

```
┌──────────┬────────────────────────────┬──────────────────────────┐
│ Threads  │            Code            │           Chat           │
│──────────│                            │──────────────────────────│
│● auth-fix│  (normal editing windows,  │ ❯ You                    │
│? refactor│   owned by this thread's   │ fix the login bug        │
│✓ docs    │   tab page)                │                          │
│          │                            │ Looking at the auth      │
│          │                            │ module…                  │
│          │                            │ ⏺ Read: src/auth.ts      │
│          │                            │ ⏺ Edit: src/auth.ts      │
│          │                            │──────────────────────────│
│          │                            │ > _                      │
└──────────┴────────────────────────────┴──────────────────────────┘
```

## Features

- **Threads sidebar** — every thread with status icon, name, and branch.
  `●` working · `?` needs your attention · `✓` idle · `✗` error.
- **Workspace per thread** — one native tab page per thread; buffers, splits,
  and a tab-local `:tcd` are naturally scoped to it.
- **Worktree isolation (opt-in)** — a new thread can get its own git worktree
  (`.worktrees/<slug>`, branch `agents/<slug>`), so parallel agents never step
  on each other's changes.
- **Custom chat panel** — driven by `claude -p` with `stream-json` in/out:
  markdown transcript, tool calls with summaries, inline diffs for edits.
- **Native permission prompts** — tool permission requests render in the chat
  panel; answer with `y`/`n`. Threads waiting on a permission flip to `?` and
  fire a notification if you're in another tab.
- **Persistence** — threads, transcripts, window layouts, and Claude session
  ids survive restarts; conversations resume via `--resume`.

## Requirements

- Neovim **0.10+**
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (`claude`) on your `$PATH`
- `git` (for worktree support)

## Install

lazy.nvim:

```lua
{
  "zenodea/acp.nvim",
  cmd = { "Acp", "AcpNew" },
  opts = {},
}
```

## Usage

| Command                   | Action                                          |
| ------------------------- | ----------------------------------------------- |
| `:Acp`           | Open the last active thread (or create one)     |
| `:AcpNew [name]` | Create a thread (asks: current checkout / worktree) |
| `:AcpToggleChat` | Show/hide the chat column in the current thread |
| `:AcpInterrupt`  | Interrupt the current thread's turn             |
| `:checkhealth acp` | Verify CLI/git/nvim setup                    |

**Sidebar**: `⏎` open · `n` new · `d` delete (offers worktree cleanup) · `r` rename.

**Chat input**: `⏎` send · `C-j` newline · `C-c` interrupt · `C-p`/`C-n` prompt history.
`y`/`n` answer a pending permission request (from the chat or input window).

**Global keymaps** (configurable, `false` to disable):
`<leader>cc` focus the chat of the current/last thread · `<leader>ct` focus the threads sidebar.
Both rebuild their panel if it was hidden, and open your last thread if you're not in one.

**Statusline**: `require("acp").statusline()` returns e.g. `●2 ?1`.

## Configuration

Defaults:

```lua
require("acp").setup({
  claude = {
    cmd = "claude",
    model = nil,            -- e.g. "claude-sonnet-5"
    extra_args = {},        -- appended to every spawn
    permissions = "prompt", -- "prompt" | "acceptEdits" | "bypassPermissions" | "plan" | "default"
    idle_timeout = 900,     -- reap idle processes (resumed on next message)
  },
  ui = {
    sidebar_width = 30,
    chat_width = 64,
    input_height = 5,
    focus_on_open = "input", -- "input" | "code" | "sidebar"
    show_thinking = true,
    show_diffs = true,
    diff_max_lines = 24,
    show_result_meta = true,
  },
  worktrees = {
    dir = ".worktrees",       -- relative to the repo root (auto-added to .git/info/exclude)
    branch_prefix = "agents/",
  },
  persist = { enabled = true, max_transcript = 2000 },
  keymaps = {
    chat = "<leader>cc",    -- focus chat (false to disable)
    threads = "<leader>ct", -- focus threads sidebar (false to disable)
  },
  notify = true,
})
```

`permissions = "prompt"` uses the CLI's stream-json control protocol
(`--permission-prompt-tool stdio`) to route tool approvals into the chat
panel. If your CLI version doesn't support it, set `permissions` to a
`--permission-mode` value like `"acceptEdits"` instead.

## How it works

- One `claude -p --input-format stream-json --output-format stream-json`
  process per active thread, spawned in the thread's worktree.
- NDJSON events drive the transcript and a per-thread status state machine;
  the `system:init` event's session id is persisted for `--resume`.
- State lives in `stdpath("data")/acp/<project-hash>.json`, keyed by
  git root; layouts are captured via `winlayout()` on tab switches and exit.
