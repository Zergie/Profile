---@diagnostic disable: undefined-field
-- Install lazy
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)



require('user.opt')
require('user.keymaps')
require('user.autocmd')
require('user.lspconfig')



require("lazy").setup({
  {
    "wellle/context.vim",
    config = function()
      -- vim.g.context_enabled = 1
      -- vim.g.context_filetype_blacklist = []
      -- vim.g.context_add_mappings = 1
      -- vim.g.context_add_autocmds = 1
      -- vim.g.context_presenter = <depends>
      -- vim.g.context_max_height = 21
      -- vim.g.context_max_per_indent = 5
      vim.g.context_max_join_parts = 8
      -- vim.g.context_ellipsis_char = '·'
      -- vim.g.context_highlight_normal = 'Normal'
      -- vim.g.context_highlight_border = 'Comment'
      -- vim.g.context_highlight_tag    = 'Special'
      -- vim.g.context_skip_regex = '^\s*\($\|#\|//\|/\*\|\*\($\|/s\|\/\)\)'
      -- vim.g.context_extend_regex = '^\s*\([]{})]\|end\|else\|case\>\|default\>\)'
      -- vim.g.context_join_regex = '^\W*$'
      -- vim.g.Context_indent = { line -> [indent(line), indent(line)] }
      -- vim.g.Context_border_indent = function('indent')
    end,
  },
  {
    "jackMort/ChatGPT.nvim",
    event = "VeryLazy",
    config = function()
      require("chatgpt").setup {
        api_key_cmd = nil,
        yank_register = "+",
        edit_with_instructions = {
          diff = false,
          keymaps = {
            close = "<ESC><ESC>",
            accept = "<C-y>",
            toggle_diff = "<C-d>",
            toggle_settings = "<C-o>",
            cycle_windows = "<Tab>",
            use_output_as_input = "<C-i>",
          },
        },
        chat = {
          loading_text = "Loading, please wait ...",
          question_sign = "", -- 🙂
          answer_sign = "ﮧ", -- 🤖
          max_line_length = 120,
          sessions_window = {
            border = {
              style = "rounded",
              text = {
                top = " Sessions ",
              },
            },
            win_options = {
              winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
            },
          },
          keymaps = {
            close = { "<ESC><ESC>" },
            yank_last = "<C-y>",
            yank_last_code = "<C-k>",
            scroll_up = "<C-u>",
            scroll_down = "<C-d>",
            new_session = "<C-n>",
            cycle_windows = "<Tab>",
            cycle_modes = "<C-f>",
            next_message = "<C-j>",
            prev_message = "<C-k>",
            select_session = "<Space>",
            rename_session = "r",
            delete_session = "d",
            draft_message = "<C-d>",
            edit_message = "e",
            delete_message = "d",
            toggle_settings = "<C-o>",
            toggle_message_role = "<C-r>",
            toggle_system_role_open = "<C-s>",
            stop_generating = "<C-x>",
          },
        },
        popup_layout = {
          default = "center",
          center = {
            width = "80%",
            height = "80%",
          },
          right = {
            width = "30%",
            width_settings_open = "50%",
          },
        },
        popup_window = {
          border = {
            highlight = "FloatBorder",
            style = "rounded",
            text = {
              top = " ChatGPT ",
            },
          },
          win_options = {
            wrap = true,
            linebreak = true,
            foldcolumn = "1",
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
          },
          buf_options = {
            filetype = "markdown",
          },
        },
        system_window = {
          border = {
            highlight = "FloatBorder",
            style = "rounded",
            text = {
              top = " SYSTEM ",
            },
          },
          win_options = {
            wrap = true,
            linebreak = true,
            foldcolumn = "2",
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
          },
        },
        popup_input = {
          prompt = "  ",
          border = {
            highlight = "FloatBorder",
            style = "rounded",
            text = {
              top_align = "center",
              top = " Prompt ",
            },
          },
          win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
          },
          submit = "<Enter>",
          submit_n = "<Enter>",
          max_visible_lines = 20,
        },
        settings_window = {
          border = {
            style = "rounded",
            text = {
              top = " Settings ",
            },
          },
          win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
          },
        },
        openai_params = {
          model = "gpt-3.5-turbo",
          frequency_penalty = 0,
          presence_penalty = 0,
          max_tokens = 300,
          temperature = 0,
          top_p = 1,
          n = 1,
        },
        openai_edit_params = {
          model = "gpt-3.5-turbo",
          frequency_penalty = 0,
          presence_penalty = 0,
          temperature = 0,
          top_p = 1,
          n = 1,
        },
        use_openai_functions_for_edits = false,
        actions_paths = { "~/AppData/Local/nvim/lua/user/chatgpt.json" },
        show_quickfixes_cmd = "Trouble quickfix",
        predefined_chat_gpt_prompts = "https://raw.githubusercontent.com/f/awesome-chatgpt-prompts/main/prompts.csv",
      }
    end,
    dependencies = {
      "MunifTanjim/nui.nvim",
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope.nvim"
    }
  },

  {
    'windwp/nvim-autopairs',
    event = "InsertEnter",
    opts = {} -- this is equalent to setup({}) function
  },


  -- -- Translator
  -- {
  --   'uga-rosa/translate.nvim',
  --   config = function ()
  --    local map = function (mode, lhs, rhs, desc)
  --      vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [Translate]" })
  --    end
  --     map('n', '<Leader>td', 'viw:Translate de<CR>', 'Translate to german')
  --     map('n', '<Leader>te', 'viw:Translate en<CR>', 'Translate to english')
  --   end
  -- },

  -- Theme inspired by Atom
  {
    'navarasu/onedark.nvim',
    lazy = false,    -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      vim.o.termguicolors = true
      vim.cmd.colorscheme('onedark')
    end
  },

  -- Git related plugins
  {
    'tpope/vim-fugitive',
    dependencies = {
      'tpope/vim-rhubarb',
    },
    config = function()
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [Fugitive]" })
      end

      map("n", "<Leader>l", "<cmd>0Gclog -- %<cr>", "git log")
      map("n", "[q", "<cmd>cprev<cr>", "Prev qf item")
      map("n", "]q", "<cmd>cnext<cr>", "Next qf item")
      map("n", "[Q", "<cmd>cfirst<cr>", "First qf item")
      map("n", "]Q", "<cmd>clast<cr>", "Last qf item")
    end
  },

  { -- File Explorer For Neovim Written In Lua
    'nvim-tree/nvim-tree.lua',
    config = function()
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [NvTree]" })
      end

      -- disable netrw at the very start of your init.lua
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1

      -- set termguicolors to enable highlight groups
      vim.opt.termguicolors = true

      -- empty setup using defaults
      require("nvim-tree").setup()

      local api = require("nvim-tree.api")
      map('n', '<Leader>x', function() api.tree.toggle({ find_file = true, update_root = true }) end, "File Explorer")
    end
  },

  { -- Fancier statusline
    'nvim-lualine/lualine.nvim',
    config = function()
      -- See `:help lualine.txt`
      require('lualine').setup {
        options = {
          icons_enabled = false,
          theme = 'onedark',
          component_separators = '|',
          section_separators = '',
        },
        sections = {
          lualine_a = { 'mode' },
          lualine_b = { 'branch', 'diff', 'diagnostics' },
          -- lualine_b = {'diagnostics'},
          lualine_c = { 'filename' },
          lualine_x = { 'encoding', 'fileformat', 'filetype' },
          lualine_y = { 'progress' },
          lualine_z = { 'location' }
        },
      }
    end
  },

  { -- extended vim motions
    'phaazon/hop.nvim',
    config = function()
      local map = function(lhs, rhs, desc)
        vim.keymap.set("", lhs, rhs, { noremap = true, silent = true, desc = desc .. " [Hop]" })
      end
      local hop = require("hop")
      -- local hint = require("hop.hint")
      -- local directions = hint.HintDirection

      hop.setup()
      -- map("f",         function () hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true }) end, "Hop forward find")
      -- map("F",         function () hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true }) end, "Hop backward find")
      -- map("t",         function () hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 }) end, "Hop forward till")
      -- map("T",         function () hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 }) end, "Hop backward till")
      map("s", function() hop.hint_words {} end, "Hop word")
      map("<Leader>j", function() hop.hint_lines {} end, "Hop word")
      map("<Leader>s", function() hop.hint_char1 {} end, "Hop 2chars forward")
    end,
  },

  -- inline key help
  {
    'folke/which-key.nvim',
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    config = function()
      local wk = require("which-key")

      wk.setup {
        plugins = {
          spelling = {
            enabled = false,
          },
        },
      }

      wk.register({
        p = {
          name = "ChatGPT",

          c = { "<cmd>ChatGPT<CR>", "ChatGPT" },
          e = { "<cmd>ChatGPTEditWithInstruction<CR>", "Edit with instruction [AI]", mode = { "n", "v" } },
          g = { "<cmd>ChatGPTRun grammar_correction<CR>", "Grammar Correction [AI]", mode = { "n", "v" } },
          t = { "<cmd>ChatGPTRun translate<CR>", "Translate [AI]", mode = { "n", "v" } },
          k = { "<cmd>ChatGPTRun keywords<CR>", "Keywords [AI]", mode = { "n", "v" } },
          d = { "<cmd>ChatGPTRun docstring<CR>", "Docstring [AI]", mode = { "n", "v" } },
          a = { "<cmd>ChatGPTRun add_tests<CR>", "Add Tests [AI]", mode = { "n", "v" } },
          o = { "<cmd>ChatGPTRun optimize_code<CR>", "Optimize Code [AI]", mode = { "n", "v" } },
          s = { "<cmd>ChatGPTRun summarize<CR>", "Summarize [AI]", mode = { "n", "v" } },
          f = { "<cmd>ChatGPTRun fix_bugs<CR>", "Fix Bugs [AI]", mode = { "n", "v" } },
          x = { "<cmd>ChatGPTRun explain_code<CR>", "Explain Code [AI]", mode = { "n", "v" } },
          r = { "<cmd>ChatGPTRun roxygen_edit<CR>", "Roxygen Edit [AI]", mode = { "n", "v" } },
          l = { "<cmd>ChatGPTRun code_readability_analysis<CR>", "Code Readability Analysis [AI]", mode = { "n", "v" } },
          p = {
            "<cmd>cd %:p:h/..<CR>" ..
            "<cmd>r!git diff --staged<CR>" ..
            "<cmd>normal V'[k<CR>" ..
            "<cmd>ChatGPTRun commit<CR>"
            ,
            "Write a commit message [AI]",
            mode = { "n", "v" }
          },
          i = {
            --"<cmd>normal ggVGyPV`]<CR>" ..
            "<cmd>normal 9ggVGyggPV`]<CR>" ..
            "<cmd>ChatGPTRun commit<CR>"
            ,
            "Write a simple commit message [AI]",
            mode = { "n", "v" }
          },

        }
      }, { prefix = "<leader>" })

      wk.register({
        g = {
          a = { "<Plug>(EasyAlign)", "Align [EasyAlign]", mode = { "n", "x" } },
        }
      })
    end
  },

  -- allows align e.g. vipga=
  {
    'junegunn/vim-easy-align',
    config = function()
    end
  },

  'mracos/mermaid.vim', -- mermaid diagram

  -- floating terminal for compling
  {
    'numToStr/FTerm.nvim',
    config = function()
      local fterm = require('FTerm')
      fterm.setup {
        cmd = "\"pwsh.exe\"",
      }

      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [FTerm]" })
      end
      map("n", "<Leader>n", fterm.toggle, "Toggle Terminal")
      map("t", "<ESC><ESC>", fterm.toggle, "Toggle Terminal")
    end
  },

  -- Fuzzy Finder (files, lsp, etc)
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim'
    },
    config = function()
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
        path_display = { "truncate" },
        defaults = {
          mappings = {
            i = {
              ['<C-u>'] = false,
              ['<C-d>'] = false,
            },
          },
        },
      }

      -- Enable telescope fzf native, if installed
      pcall(require('telescope').load_extension, 'fzf')


      require('user.telescope')
      local telescope = require('telescope.builtin')
      local themes = require('telescope.themes')
      local minimal_theme = themes.get_dropdown {
        winblend      = 10,
        previewer     = false,
        layout_config = {
          width = 0.5,
        },
      }
      -- local cursor_theme = themes.get_cursor {
      --     winblend  = 10,
      --     previewer = true,
      --     layout_config = {
      --       height = 0.5,
      --       width  = 0.8,
      --     },
      -- }
      local cursor_minimal_theme = themes.get_cursor {
        winblend      = 20,
        previewer     = false,
        layout_config = {
          height = 0.25,
        },
      }

      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
      end

      map('n', '<leader><space>', function() telescope.buffers(minimal_theme) end, 'Find existing buffers')
      map('n', '<leader>sf', function() telescope.find_files(minimal_theme) end, '[S]earch [F]iles')
      map('n', '<leader>so', function() telescope.oldfiles(minimal_theme) end, '[S]earch in old files')
      map('n', 'z=', function() telescope.spell_suggest(cursor_minimal_theme) end, 'Spell Suggest')
      map('n', '<leader>/', telescope.current_buffer_fuzzy_find, 'Search in current buffer')
      map("n", "<Leader>sb", telescope.builtin, "[S]earch [B]uiltin")
      map("n", "<Leader>sm", telescope.marks, "[S]earch [M]arks")
      map("n", "<Leader>sr", telescope.resume, "[S]earch [R]esume")
      map('n', '<leader>sh', telescope.help_tags, '[S]earch [H]elp')
      map('n', '<leader>sw', function() telescope.grep_string() end, '[S]earch current [W]ord')
      map('n', '<leader>sg', telescope.live_grep, '[S]earch by [G]rep')
      map('n', '<leader>sd', telescope.diagnostics, '[S]earch [D]iagnostics')

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
    end
  },


  -- Add indentation guides even on blank lines
  {
    'lukas-reineke/indent-blankline.nvim',
    config = function()
      -- See `:help indent_blankline.txt`
      local fghighlight = {
        "Fg0",
        "Fg1",
        "Fg2",
        "Fg3",
        "Fg4",
        "Fg5",
        "Fg6",
      }
      local bghighlight = {
        "Bg0",
        "Bg1",
        "Bg2",
        "Bg3",
        "Bg4",
        "Bg5",
        "Bg6",
      }

      local hooks = require "ibl.hooks"
      -- create the highlight groups in the highlight setup hook, so they are reset
      -- every time the colorscheme changes
      hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
        vim.api.nvim_set_hl(0, "Fg0", { fg = "#4A3FD0" })
        vim.api.nvim_set_hl(0, "Fg1", { fg = "#CE22B0" })
        vim.api.nvim_set_hl(0, "Fg2", { fg = "#FF3E83" })
        vim.api.nvim_set_hl(0, "Fg3", { fg = "#FF7F5C" })
        vim.api.nvim_set_hl(0, "Fg4", { fg = "#FFBF4E" })
        vim.api.nvim_set_hl(0, "Fg5", { fg = "#F9F871" })
        vim.api.nvim_set_hl(0, "Fg6", { fg = "#56B6C2" })

        vim.api.nvim_set_hl(0, "Bg0", { bg = "#E06C75" })
        vim.api.nvim_set_hl(0, "Bg1", { bg = "#E5C07B" })
        vim.api.nvim_set_hl(0, "Bg2", { bg = "#61AFEF" })
        vim.api.nvim_set_hl(0, "Bg3", { bg = "#D19A66" })
        vim.api.nvim_set_hl(0, "Bg4", { bg = "#98C379" })
        vim.api.nvim_set_hl(0, "Bg5", { bg = "#C678DD" })
        vim.api.nvim_set_hl(0, "Bg6", { bg = "#56B6C2" })
      end)

      require('ibl').setup {
        indent = {
          char = '|',
          highlight = fghighlight,
        },
        -- whitespace = {
        --   remove_blankline_trail = false,
        --   highlight = bghighlight,
        -- },
        scope = {
          enabled = true,
          char = ' ',
          highlight = bghighlight,
        },
      }
    end
  },
  { -- "gc" to comment visual regions/lines
    'numToStr/Comment.nvim',
    config = function()
      require('Comment').setup()
    end
  },
  'tpope/vim-sleuth',   -- Detect tabstop and shiftwidth automatically
  'wilriker/gcode.vim', -- gcode syntax


  -- LSP Configuration & Plugins
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { -- Automatically install LSPs to stdpath for neovim
        'williamboman/mason.nvim',
        dependencies = {
          'williamboman/mason-lspconfig.nvim',
          { -- Additional lua configuration, makes nvim stuff amazing
            'folke/neodev.nvim',
            config = function()
              require('neodev').setup()
            end
          }
        },
        config = function()
          if vim.loop.os_uname().sysname ~= 'Linux' then
            local servers = {
              lua_ls = {
                Lua = {
                  workspace = { checkThirdParty = false },
                  telemetry = { enable = false },
                },
              },
              jsonls = {
                schemas = require('schemastore').json.schemas(),
                validate = { enable = true },
              },
              pyright = {},
              lemminx = {
                filetypes = { "xml", "xsd", "xsl", "xslt", "svg", "ps1xml" },
                --     cmd       = { 'c:/GIT/Profile/neovim/lsp_server/lemminx/lemminx-win32.exe' },
              },
              omnisharp = {
                -- Enables support for reading code style, naming convention and analyzer
                -- settings from .editorconfig.
                enable_editorconfig_support = true,
                -- If true, MSBuild project system will only load projects for files that
                -- were opened in the editor. This setting is useful for big C# codebases
                -- and allows for faster initialization of code navigation features only
                -- for projects that are relevant to code that is being edited. With this
                -- setting enabled OmniSharp may load fewer projects and may thus display
                -- incomplete reference lists for symbols.
                enable_ms_build_load_projects_on_demand = false,
                -- Enables support for roslyn analyzers, code fixes and rulesets.
                enable_roslyn_analyzers = true,
                -- Specifies whether 'using' directives should be grouped and sorted during
                -- document formatting.
                organize_imports_on_format = false,
                -- Enables support for showing unimported types and unimported extension
                -- methods in completion lists. When committed, the appropriate using
                -- directive will be added at the top of the current file. This option can
                -- have a negative impact on initial completion responsiveness,
                -- particularly for the first few completion sessions after opening a
                -- solution.
                enable_import_completion = false,
                -- Specifies whether to include preview versions of the .NET SDK when
                -- determining which version to use for project loading.
                sdk_include_prereleases = true,
                -- Only run analyzers against open files when 'enableRoslynAnalyzers' is
                -- true
                analyze_open_documents_only = false,
              },
              powershell_es = {},
              arduino_language_server = {
                cmd = {
                  'C:\\Users\\user\\AppData\\Local\\nvim-data\\mason\\bin\\arduino-language-server.cmd',

                  '-cli',
                  'C:\\Program Files\\Arduino CLI\\arduino-cli.exe',

                  '-cli-config',
                  'C:\\Users\\user\\AppData\\Local\\Arduino15\\arduino-cli.yaml',

                  '-clangd',
                  'C:\\Users\\user\\AppData\\Local\\nvim-data\\mason\\bin\\clangd.cmd',

                  '-fqbn',
                  'arduino:avr:nano',

                  -- '-log',
                  -- '-logpath',
                  -- 'C:\\GIT\\mpcnc_post_processor\\handwheel\\firmware',
                }
              },
            }

            -- nvim-cmp supports additional completion capabilities, so broadcast that to servers
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

            -- Setup mason so it can manage external tooling
            require('mason').setup()

            -- Ensure the servers above are installed
            local mason_lspconfig = require 'mason-lspconfig'

            mason_lspconfig.setup {
              ensure_installed = vim.tbl_keys(servers),
            }

            local tableHasKey = function(table, key) return table[key] ~= nil end

            mason_lspconfig.setup_handlers {
              function(server_name)
                if tableHasKey(servers, server_name) and tableHasKey(servers[server_name], 'cmd') then
                  require('lspconfig')[server_name].setup {
                    cmd = servers[server_name]['cmd'],
                    capabilities = capabilities,
                    on_attach = On_attach,
                    settings = servers[server_name],
                  }
                else
                  require('lspconfig')[server_name].setup {
                    capabilities = capabilities,
                    on_attach = On_attach,
                    settings = servers[server_name],
                  }
                end
              end,
            }
          end
        end
      },

      -- Useful status updates for LSP
      {
        'j-hui/fidget.nvim',
        config = function()
          require('fidget').setup()
        end
      },

      -- A Neovim Lua plugin providing access to the SchemaStore catalog.
      'b0o/schemastore.nvim',
    },
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    event = "InsertEnter",
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-path',
      'hrsh7th/nvim-cmp',
      'saadparwaiz1/cmp_luasnip',
      { -- Snippets
        'L3MON4D3/LuaSnip',
        config = function()
          require("luasnip.loaders.from_snipmate").lazy_load({ paths = { "./snippets" } })
          require("luasnip.loaders.from_snipmate").lazy_load()
        end,
        dependencies = {
          "honza/vim-snippets",
        },
      },
      { -- Dictionary
        'uga-rosa/cmp-dictionary',
        config = function()
          local dict = require("cmp_dictionary")
          dict.setup({
            exact = 2,
            first_case_insensitive = true,
            document = false,
            document_command = "wn %s -over",
            async = false,
            sqlite = false,
            max_items = -1,
            capacity = 5,
            debug = false,
          })
          dict.switcher({
            filetype = {
              gitcommit = "C:/GIT/Profile/neovim/spell/en_us.dict",
            },
          })
        end
      }
    },
    config = function()
      local cmp = require('cmp')
      local ls = require('luasnip')

      cmp.setup {
        snippet = {
          expand = function(args)
            ls.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert {
          ["<C-u>"] = cmp.mapping.scroll_docs(-2),
          ["<C-d>"] = cmp.mapping.scroll_docs(2),
          ["<C-h>"] = cmp.mapping.complete({ reason = cmp.ContextReason.Manual }),
          -- ["<C-e>"] = cmp.mapping.abort(),
          ["<Tab>"] = cmp.mapping.confirm({
            behavior = cmp.ConfirmBehavior.Insert,
            select = true, -- use first result if none explicitly selected
          }),
          -- ["<Tab><Tab>"] = function (fallback)
          --   if cmp.visible then
          --     cmp.select_next_item()
          --     cmp.select_next_item()
          --     cmp.confirm({ behavior = cmp.ConfirmBehavior.Insert })
          --   else
          --     fallback()
          --   end
          -- end,
          -- ["<Tab><Tab><Tab>"] = function (fallback)
          --   if cmp.visible then
          --     cmp.select_next_item()
          --     cmp.select_next_item()
          --     cmp.select_next_item()
          --     cmp.confirm({ behavior = cmp.ConfirmBehavior.Insert })
          --   else
          --     fallback()
          --   end
          -- end,
          -- ["<C-n>"] = cmp.mapping.select_next_item({ behavior = cmp.SelectBehavior.Select }),
          -- ["<C-p>"] = cmp.mapping.select_prev_item({ behavior = cmp.SelectBehavior.Select }),
          ['<C-n>'] = cmp.mapping(function() ls.jump(1) end, { 'i', 's' }),
          ['<C-p>'] = cmp.mapping(function() ls.jump(-1) end, { 'i', 's' }),
          ['<C-e>'] = cmp.mapping(function() ls.change_choice(1) end, { 'i', 's' }),
        },
        formatting = {
          format = function(entry, vim_item)
            if entry.source.name == 'dictionary' then
              vim_item.kind = 'Dictionary'
            end
            vim_item.dup = ({
              buffer = 0,
              dictionary = 0,
            })[entry.source.name] or 0
            vim_item.color = 'red'

            return vim_item
          end
        },
        sources = {
          { name = 'luasnip',        priority = 1, option = { keyword_pattern = [[\k\+]] } },
          { name = 'nvim_lsp',       priority = 2, max_items = 10,                         option = {
            keyword_pattern = [[\k\+]] } },
          { name = 'buffer',         priority = 3, max_items = 5,                          option = {
            keyword_pattern = [[\k\+]] } },
          { name = 'dictionary',     priority = 4, max_items = 5,                          keyword_length = 2,
                                                                                                                                     option = {
              keyword_pattern = [[\k\+]] } },
          { name = 'path',           priority = 5 },
          { name = 'luasnip_choice', priority = 6 },
          sorting = {
            priority_weight = 2.0,
            comparators = {
              cmp.config.compare.recently_used,
              cmp.config.compare.score, -- based on :  score = score + ((#sources - (source_index - 1)) * sorting.priority_weight)
              cmp.config.compare.locality,
              cmp.config.compare.offset,
              cmp.config.compare.order,
            },
          },
        },
        performance = {
          max_view_entries = 50,
        },
        window = {
          completion = cmp.config.window.bordered(),
          documentation = cmp.config.window.bordered(),
        },
        experimental = {
          ghost_text = true,
        },
        completion = {
          keyword_pattern = [[\k\+]],
        },
      }

      require("user.snippets")
    end
  },
})




-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
--  Add any additional override configuration in the following tables. They will be passed to
--  the `settings` field of the server config. You must look up that documentation yourself.
