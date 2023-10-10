-- Vim filetype plugin file
--     Language: Arduino
--   Maintainer:	Wolfgang Puchinger <wpuchinger@rocom-service.de>

local map = function (mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer=0, noremap = true, silent = true, desc = desc })
end

-- " Change these as desired
-- map("n", "<leader>ma", "<cmd>ArduinoAttach<cr>", "ArduinoAttach")
-- map("n", "<leader>mv", "<cmd>ArduinoVerify<cr>", "ArduinoVerify")
-- map("n", "<leader>mu", "<cmd>ArduinoUpload<cr>", "ArduinoUpload")
-- map("n", "<leader>mk", "<cmd>ArduinoUploadAndSerial<cr>", "ArduinoUploadAndSerial")
-- map("n", "<leader>ms", "<cmd>ArduinoSerial<cr>", "ArduinoSerial")
-- map("n", "<leader>mb", "<cmd>ArduinoChooseBoard<cr>", "ArduinoChooseBoard")
-- map("n", "<leader>mp", "<cmd>ArduinoChooseProgrammer<cr>", "ArduinoChooseProgrammer")

local cli = ". 'C:/Program Files/Arduino CLI/arduino-cli.exe'"
local port = "-p COM4;"

map("n", "<Leader>mk", function ()
    vim.cmd("wa")
    require('FTerm').run(";"
	.. "pushd '" .. vim.fn.expand("%:p:h") .. "';"
	.. cli .. " compile " .. port
	.. "if ($LASTEXITCODE -eq 0) {"
	.. cli .. " upload '" .. vim.fn.expand("%:p:h") .. "' " .. port
	.. "}"
	.. "popd"
    )
end,  "Upload sketch")

map("n", "<Leader>ms", function ()
    require('FTerm').run(";"
	.. cli .. " monitor " .. port
    )
end,  "Open serial")
