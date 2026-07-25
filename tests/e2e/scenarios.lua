---Declarative scripts for the fake ACP agent (tests/e2e/fake_agent.lua).
---A scenario is a list of turns; turn N answers the N-th session/prompt
---(the last turn repeats). Each turn is a list of steps executed in order:
---  { chunk = "text" }          agent_message_chunk
---  { tool_call = {...} }       tool_call update (toolCallId, title, kind, ...)
---  { tool_update = {...} }     tool_call_update (merged into the call)
---  { plan = { entries } }      plan update
---  { permission = {...} }      session/request_permission; blocks on the answer
---  { wait_cancel = true }      block until session/cancel; reply cancelled
---  { exit = code }             kill the agent process mid-turn
---  { stop = "reason" }         stopReason for the prompt response (default end_turn)

local DIFF = {
  { type = "diff", oldText = "local a = 1\nlocal b = 2", newText = "local a = 1\nlocal b = 99" },
}

return {
  greeting = {
    turns = {
      { { chunk = "Hello " }, { chunk = "world" } },
    },
  },

  question = {
    turns = {
      { { chunk = "Should I continue?" } },
    },
  },

  tool_diff = {
    turns = {
      {
        { tool_call = { toolCallId = "t1", title = "Edit foo.lua", kind = "edit", status = "in_progress" } },
        { tool_update = { toolCallId = "t1", status = "completed", content = DIFF } },
        { chunk = "Edited." },
      },
    },
  },

  planning = {
    turns = {
      {
        {
          plan = {
            { content = "Read the spec", status = "completed", priority = "high" },
            { content = "Write the parser", status = "in_progress", priority = "high" },
            { content = "Add tests", status = "pending", priority = "medium" },
          },
        },
        { chunk = "Planned." },
      },
    },
  },

  -- One spawn that finishes and one still going when the turn ends, so both
  -- subagent states are observable without racing the fake agent.
  delegating = {
    turns = {
      {
        { tool_call = { toolCallId = "s1", title = "Task: audit the parser", kind = "other", status = "in_progress" } },
        { tool_update = { toolCallId = "s1", status = "completed" } },
        { tool_call = { toolCallId = "s2", title = "Explore the loader", kind = "other", status = "in_progress" } },
        { tool_call = { toolCallId = "t1", title = "Edit foo.lua", kind = "edit", status = "in_progress" } },
        { chunk = "Delegated." },
      },
    },
  },

  -- Reports a location, so follow mode has somewhere to jump. README.md is
  -- relative to the thread cwd, which the harness points at the repo root.
  follow_edit = {
    turns = {
      {
        {
          tool_call = {
            toolCallId = "t1",
            title = "Edit README.md",
            kind = "edit",
            status = "completed",
            locations = { { path = "README.md", line = 3 } },
          },
        },
        { chunk = "Edited." },
      },
    },
  },

  permission = {
    turns = {
      {
        { tool_call = { toolCallId = "t1", title = "Edit foo.lua", kind = "edit", status = "pending" } },
        {
          permission = {
            title = "Edit foo.lua",
            options = {
              { optionId = "allow", kind = "allow_once", name = "Allow" },
              { optionId = "reject", kind = "reject_once", name = "Reject" },
            },
          },
        },
        { tool_update = { toolCallId = "t1", status = "completed", content = DIFF } },
        { chunk = "Done." },
      },
      { { chunk = "Second turn." } },
    },
  },

  cancel_me = {
    turns = {
      { { chunk = "working..." }, { wait_cancel = true } },
    },
  },

  -- A tool call left in flight for the whole turn, so the spinner next to it
  -- can be observed without racing the agent.
  slow_tool = {
    turns = {
      {
        { tool_call = { toolCallId = "t1", title = "Run the suite", kind = "execute", status = "in_progress" } },
        { wait_cancel = true },
      },
    },
  },

  crash_mid_turn = {
    turns = {
      { { chunk = "about to die" }, { exit = 3 } },
    },
  },
}
