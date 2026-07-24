# Manual smoke checklist

Things the headless suites cannot see. Run through these in a real terminal
after UI-affecting changes:

- [ ] Sidebar + tool icons render in your font (agent glyphs, `󰖷`, the
      pencil for edits, `⧗` in the queue winbar) — no tofu boxes, no
      double-width overlap swallowing spaces.
- [ ] Diff colors read well against your colorscheme: add/delete line
      backgrounds, the brighter intra-line changed span, dim `⋯` hunk
      separators.
- [ ] Plan entries: active step stands out, completed steps show `✓`.
- [ ] Queue editor float: sensible size on a small window, title readable,
      `:q` applies and closes only the float.
- [ ] Permission prompt: `[y] Allow`-style hints visible, `y`/`a`/`n`
      answer it from both chat and input windows.
- [ ] `gd` on an edit tool call jumps to the file/line; `gf` follow mode
      tracks the agent live.
- [ ] Statusline component (`require("acp").statusline()`) in your setup.
