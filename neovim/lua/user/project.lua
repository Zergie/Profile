-- Project commands load the floating terminal only when they run.
local map = function(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
end

local run_commands = function(commands)
  local fterm = require('FTerm')
  fterm.run(";pushd " .. vim.fn.getcwd())
  for _, cmd in ipairs(commands) do fterm.run(cmd) end
  fterm.run(";popd")
end

local save = function()
  local buffers = ""
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(buf, 'modified') then
      buffers = buffers .. ' "' .. vim.uri_from_bufnr(buf) .. '"'
    end
  end
  print(vim.inspect(buffers))

  vim.cmd("wa")
  local cmd_table = {
    ["C:\\GIT\\TauOffice\\tau-office\\source"] = {
      "Import-Msaccess -Path " .. buffers .. " -Compile",
    },
  }

  if not (buffers == nil or buffers == "") then
    run_commands(cmd_table[vim.fn.getcwd()] or { "" })
  end
end
map("n", "<Leader>ms", save, "Save project")

local build = function()
  vim.cmd("wa")
  local cmd_table = {
    ["C:\\GIT\\TauOffice\\Admintool"] = {
      "./make.ps1",
    },
    ["C:\\GIT\\TauOffice\\tau-office\\source"] = {
      "sudo ../make.ps1 -dev",
    },
  }
  run_commands(cmd_table[vim.fn.getcwd()] or { "sudo ./make.ps1" })
end
map("n", "<Leader>mk", build, "Build project")

local run = function()
  local cmd_table = {
    ["C:\\GIT\\TauOffice\\Admintool"] = {
      "Stop-Process -ProcessName AdminTool.App -ErrorAction SilentlyContinue",
      ". 'C:/Program Files (x86)/Tau-Office/Admintool/AdminTool.App.exe'",
      "Watch-Log Admintool.log -Exit",
    },
    ["C:\\GIT\\TauOffice\\tau-office\\source"] = {
      "ii ../bin/tau-office.mdb",
      "sleep 5;Watch-Log TauError.log -Exit",
    },
  }
  run_commands(cmd_table[vim.fn.getcwd()] or {})
end
map("n", "<Leader>mr", run, "Run project")

map("n", "<Leader>mm", function()
  vim.cmd("wa")
  require('FTerm').run(
  ";$history = Get-History; $history | Select-Object -Last 1 |% { Write-Host -ForegroundColor Cyan $_ ; Invoke-Expression $_ }; Clear-History; $history | Add-History")
end, "Repeat last command")
