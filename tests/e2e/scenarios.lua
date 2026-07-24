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

  crash_mid_turn = {
    turns = {
      { { chunk = "about to die" }, { exit = 3 } },
    },
  },
}
