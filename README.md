# acp.nvim

Zed-style agent threads for Neovim, built on the
[Agent Client Protocol](https://agentclientprotocol.com) — Claude Code,
Gemini CLI, Codex, and any other ACP agent, each in its own workspace.

Each **thread** owns a full workspace: its own tab page, its own window layout,
optionally its own **git worktree** — and a chat panel talking to its own agent
session. A sidebar shows every thread with a live status, so you can run
several agents in parallel and see at a glance which one is working, which one
is waiting on you, and which one is done.

```
┌────────────┬──────────────────────────┬────────────────────────────┐
│ Threads    │           Chat           │            Code            │
│────────────│──────────────────────────│                            │
│● ✳ auth-fix│ ❯ You                    │  (normal editing windows,  │
│? ⬡ refactor│ fix the login bug        │   owned by this thread's   │
│✓ ✳ docs    │                          │   tab page)                │
│            │ Looking at the auth      │                            │
│            │ module…                  │                            │
│            │ ⏺ Read src/auth.ts       │                            │
│            │ ⏺ Edit src/auth.ts …     │                            │
│            │──────────────────────────│                            │
│            │ > _                      │                            │
└────────────┴──────────────────────────┴────────────────────────────┘
```

## Features

- **Any ACP agent, per thread** — Claude Code (`✳`) and Codex (`⬡`) out of the
  box; add Gemini or anything from the
  [ACP registry](https://agentclientprotocol.com/get-started/registry).
  Creating a thread asks which agent it should run, and the sidebar shows the
  agent's icon next to each thread.
- **Threads sidebar** — every thread with status icon, agent icon, name, and
  branch. `●` working · `?` needs your attention · `✓` idle · `✗` error.
  The cursor snaps to thread lines; the native tabline is hidden (the sidebar
  *is* the workspace switcher), and switching threads keeps your cursor in the
  same kind of window — sidebar stays sidebar, code stays code.
- **Workspace per thread** — one native tab page per thread; buffers, splits,
  and a tab-local `:tcd` are naturally scoped to it.
- **Worktree isolation (opt-in)** — a new thread can get its own git worktree
  (`.worktrees/<slug>`, branch `agents/<slug>`), so parallel agents never step
  on each other's changes.
- **Live chat panel** — streamed response chunks, thought chunks, plans, and
  tool calls that update in place (pending → running → done) with inline diffs.
- **Native permission prompts** — ACP `session/request_permission` renders in
  the chat panel with the agent's own options (allow once/always, reject).
  Threads waiting on a permission flip to `?` and fire a notification.
- **Editor-aware file access** — the ACP fs capability routes the agent's
  reads/writes through Neovim: it sees your unsaved buffer contents, and its
  edits land in your open buffers.
- **Persistence** — threads, transcripts, window layouts, and agent session
  ids survive restarts; conversations resume via ACP `session/load`.

## Requirements

- Neovim **0.10+**
- Node.js (the default Claude adapter runs via `npx`)
- An authenticated [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
  login (or `ANTHROPIC_API_KEY`) for the default agent
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

| Command            | Action                                              |
| ------------------ | --------------------------------------------------- |
| `:Acp`             | Open the last active thread (or create one)         |
| `:AcpNew [name]`   | Create a thread (asks: agent, checkout/worktree)    |
| `:AcpToggleChat`   | Show/hide the chat column in the current thread     |
| `:AcpInterrupt`    | Interrupt the current thread's turn                 |
| `:checkhealth acp` | Verify agents/git/nvim setup                        |

**Sidebar**: `⏎` open · `n` new · `d` delete (offers worktree cleanup) · `r` rename.

**Chat input**: `⏎` send · `C-j` newline · `C-c` interrupt · `C-p`/`C-n` prompt history.
Permission prompts show their keys inline (typically `y` allow once · `a` always
allow · `n` reject), answerable from the chat or input window.

**Global keymaps** (configurable, `false` to disable):
`<leader>cc` focus the chat of the current/last thread · `<leader>ct` focus the
threads sidebar. Both rebuild their panel if it was hidden, and open your last
thread if you're not in one.

**Statusline**: `require("acp").statusline()` returns e.g. `●2 ?1`.

## Configuration

Defaults:

```lua
require("acp").setup({
  agents = {
    claude = { cmd = { "npx", "-y", "@agentclientprotocol/claude-agent-acp" }, icon = "✳" },
    codex  = { cmd = { "npx", "-y", "@agentclientprotocol/codex-acp" }, icon = "⬡" },
    -- gemini = { cmd = { "gemini", "--experimental-acp" }, icon = "◆" },
    -- Each entry may also set `env = { KEY = "value" }`.
  },
  default_agent = "claude",
  idle_timeout = 900,        -- reap idle agent processes (session/load revives them)
  ui = {
    sidebar_width = 30,
    chat_width = 64,
    input_height = 5,
    hide_tabline = true,     -- threads are tabs; the sidebar replaces the tabline
    focus_on_open = "keep",  -- "keep" | "input" | "code" | "sidebar"
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

## How it works

- One ACP agent process per active thread (JSON-RPC 2.0 over stdio), spawned
  in the thread's worktree: `initialize` → `session/new` → `session/prompt`.
- `session/update` notifications drive the transcript (message/thought chunks,
  tool calls, plans) and a per-thread status state machine.
- Agent-to-editor requests are served by the plugin: `session/request_permission`
  becomes an inline prompt, `fs/read_text_file` / `fs/write_text_file` go
  through your buffers.
- State lives in `stdpath("data")/acp/<project-hash>.json`, keyed by git root;
  layouts are captured via `winlayout()` on tab switches and exit. Reopened
  threads reload their conversation with `session/load` when the agent
  supports it.
