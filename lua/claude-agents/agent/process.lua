local M = {}

---Spawn a line-oriented NDJSON process.
---@param opts {args: string[], cwd: string, on_line: fun(line: string), on_exit: fun(code: integer), on_stderr: fun(text: string)|nil}
---@return integer|nil job_id, string|nil err
function M.spawn(opts)
  local pending = "" -- partial line carried between on_stdout calls

  local job = vim.fn.jobstart(opts.args, {
    cwd = opts.cwd,
    stdin = "pipe",
    on_stdout = function(_, data, _)
      -- data is a list where the first entry continues the previous partial
      -- line and the last entry is a new partial line ("" when complete).
      if not data then
        return
      end
      data[1] = pending .. data[1]
      pending = table.remove(data)
      for _, line in ipairs(data) do
        if line ~= "" then
          local ok, err = pcall(opts.on_line, line)
          if not ok then
            vim.schedule(function()
              vim.notify("claude-agents event error: " .. tostring(err), vim.log.levels.ERROR)
            end)
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if opts.on_stderr and data then
        local text = vim.trim(table.concat(data, "\n"))
        if text ~= "" then
          opts.on_stderr(text)
        end
      end
    end,
    on_exit = function(_, code, _)
      if pending ~= "" and pending:sub(1, 1) == "{" then
        pcall(opts.on_line, pending)
        pending = ""
      end
      opts.on_exit(code)
    end,
  })

  if job <= 0 then
    return nil, "failed to spawn: " .. table.concat(opts.args, " ")
  end
  return job, nil
end

---@param job integer
---@param tbl table encoded as one NDJSON line on stdin
---@return boolean ok
function M.send(job, tbl)
  local ok, encoded = pcall(vim.json.encode, tbl)
  if not ok then
    return false
  end
  return pcall(vim.fn.chansend, job, encoded .. "\n") and true or false
end

---@param job integer
function M.kill(job)
  pcall(vim.fn.jobstop, job)
end

---@param job integer|nil
---@return boolean
function M.alive(job)
  if not job then
    return false
  end
  local ok, res = pcall(vim.fn.jobwait, { job }, 0)
  return ok and res[1] == -1
end

return M
