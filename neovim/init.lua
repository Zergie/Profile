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
   -- Translator
   {
     'uga-rosa/translate.nvim',
     config = function ()
      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [Translate]" })
      end
       map('n', '<Leader>td', 'viw:Translate de<CR>', 'Translate to german')
       map('n', '<Leader>te', 'viw:Translate en<CR>', 'Translate to english')
     end
   },

   -- Theme inspired by Atom
   {
    'navarasu/onedark.nvim',
    lazy = false,    -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function ()
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
    config = function ()
      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [Fugitive]" })
      end

      map("n", "<Leader>l", "<cmd>0Gclog -- %<cr>", "git log")
      map("n", "[q",        "<cmd>cprev<cr>",       "Prev qf item")
      map("n", "]q",        "<cmd>cnext<cr>",       "Next qf item")
      map("n", "[Q",        "<cmd>cfirst<cr>",      "First qf item")
      map("n", "]Q",        "<cmd>clast<cr>",       "Last qf item")
    end
  },

  { -- File Explorer For Neovim Written In Lua
    'nvim-tree/nvim-tree.lua',
    config = function ()
      local map = function (mode, lhs, rhs, desc)
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
      map('n', '<Leader>x', function () api.tree.toggle({find_file=true, update_root=true}) end, "File Explorer")
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
          lualine_a = {'mode'},
          lualine_b = {'branch', 'diff', 'diagnostics'},
          -- lualine_b = {'diagnostics'},
          lualine_c = {'filename'},
          lualine_x = {'encoding', 'fileformat', 'filetype'},
          lualine_y = {'progress'},
          lualine_z = {'location'}
        },
      }
    end
  },

  { -- extended vim motions
    'phaazon/hop.nvim',
    config = function()
      local map = function (lhs, rhs, desc)
        vim.keymap.set("", lhs, rhs, { noremap = true, silent = true, desc = desc .. " [Hop]" })
      end
      local hop = require("hop")
      local hint = require("hop.hint")
      local directions = hint.HintDirection

      hop.setup()
      -- map("f",         function () hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true }) end, "Hop forward find")
      -- map("F",         function () hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true }) end, "Hop backward find")
      -- map("t",         function () hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 }) end, "Hop forward till")
      -- map("T",         function () hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 }) end, "Hop backward till")
      map("<Leader>w", function () hop.hint_words{ } end, "Hop word")
      map("<Leader>j", function () hop.hint_lines{ } end, "Hop word")
      map("<Leader>j", function () hop.hint_lines{ } end, "Hop word")
      map("s",         function () hop.hint_char1{ } end, "Hop 2chars forward")
    end,
  },

  -- inline key help
  {
    'folke/which-key.nvim',
    config = function ()
      require("which-key").setup {
          plugins = {
              spelling = {
                  enabled = false,
                  suggestions = 20,
              }
          }
      }
    end
  },

  -- allows align e.g. vipga=
  {
    'junegunn/vim-easy-align',
    config = function ()
      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [EasyAlign]" })
      end
      map("x", "ga", "<Plug>(EasyAlign)", "Align")
      map("n", "ga", "<Plug>(EasyAlign)", "Align")
    end
  },

  'mracos/mermaid.vim', -- mermaid diagram

  -- floating terminal for compling
  {
    'numToStr/FTerm.nvim',
    config = function ()
      local fterm = require('FTerm')
      fterm.setup{
        cmd = "\"pwsh.exe\"",
      }

      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. " [FTerm]" })
      end
      map("n", "<Leader>n",  fterm.toggle, "Toggle Terminal")
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
    config = function ()
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
          winblend  = 10,
          previewer = false,
          layout_config = {
            width = 0.5,
          },
      }
      local cursor_theme = themes.get_cursor {
          winblend  = 10,
          previewer = true,
          layout_config = {
            height = 0.5,
            width  = 0.8,
          },
      }
      local cursor_minimal_theme = themes.get_cursor {
          winblend  = 20,
          previewer = false,
          layout_config = {
            height = 0.25,
          },
      }

      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
      end

      -- map('n', '<leader>/',       function() telescope.current_buffer_fuzzy_find(minimal_theme) end, '[/] Fuzzily search in current buffer]' )
      map('n', '<leader><space>', function() telescope.buffers(minimal_theme) end,              'Find existing buffers')
      map('n', '<leader>sf',      function() telescope.find_files(minimal_theme) end,           '[S]earch [F]iles' )
      map('n', '<leader>so',      function() telescope.oldfiles(minimal_theme) end,             '[S]earch in old files')
      map('n', 'z=',              function() telescope.spell_suggest(cursor_minimal_theme) end, 'Spell Suggest')
      map('n', '<leader>/',       telescope.current_buffer_fuzzy_find,                          'Search in current buffer' )
      map("n", "<Leader>sb",      telescope.builtin,                                            "[S]earch [B]uiltin")
      map("n", "<Leader>sm",      telescope.marks,                                              "[S]earch [M]arks")
      map("n", "<Leader>sr",      telescope.resume,                                             "[S]earch [R]esume")
      map('n', '<leader>sh',      telescope.help_tags,                                          '[S]earch [H]elp' )
      map('n', '<leader>sw',      function() telescope.grep_string(themes.get_dropdown()) end,  '[S]earch current [W]ord' )
      map('n', '<leader>sg',      telescope.live_grep,                                          '[S]earch by [G]rep' )
      map('n', '<leader>sd',      telescope.diagnostics,                                        '[S]earch [D]iagnostics' )

      local run_commands = function (commands)
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
              run_commands(cmd_table[vim.fn.getcwd()] or {""})
          end
      end
      map("n", "<Leader>ms", save,  "Save project")

      local build = function ()
          vim.cmd("wa")
          local cmd_table = {
              ["C:\\GIT\\TauOffice\\Admintool"] = {
                  "./make.ps1",
              },
              ["C:\\GIT\\TauOffice\\tau-office\\source"] = {
                  "sudo ../make.ps1 -dev",
              },
          }
          run_commands(cmd_table[vim.fn.getcwd()] or {"sudo ./make.ps1"})
      end
      map("n", "<Leader>mk", build,  "Build project")

      local run = function ()
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
      map("n", "<Leader>mr", run,  "Run project")

      map("n", "<Leader>mm", function ()
          vim.cmd("wa")
          require('FTerm').run("; r")
      end,  "Repeat last command")
    end
  },


  -- Add indentation guides even on blank lines
  {
  'lukas-reineke/indent-blankline.nvim',
    config = function ()
      -- See `:help indent_blankline.txt`
      require('indent_blankline').setup {
        char = '┊',
        show_trailing_blankline_indent = false,
      }
    end
  },
  { -- "gc" to comment visual regions/lines
    'numToStr/Comment.nvim',
    config = function ()
      require('Comment').setup()
    end
  },
  'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically
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
            config = function ()
              require('neodev').setup()
            end
          },
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

            mason_lspconfig.setup_handlers {
              function(server_name)
                require('lspconfig')[server_name].setup {
                  capabilities = capabilities,
                  on_attach = On_attach,
                  settings = servers[server_name],
                }
              end,
            }
          end
        end
      },

      -- Useful status updates for LSP
      {
        'j-hui/fidget.nvim',
        config = function ()
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
          require("luasnip.loaders.from_snipmate").lazy_load()
          require("luasnip.loaders.from_snipmate").lazy_load({ paths = { "./snippets" } })
        end,
        dependencies = {
          "honza/vim-snippets",
        },
      },
      { -- Dictionary
        'uga-rosa/cmp-dictionary',
        config = function ()
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
      },
    },
    config = function()
      local cmp = require('cmp')
      local luasnip = require('luasnip')

      cmp.setup {
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert {
          ['<C-d>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<Tab>'] = cmp.mapping.confirm {
            behavior = cmp.ConfirmBehavior.Replace,
            select = true,
          },
          ['<C-n>'] = cmp.mapping(function() luasnip.jump(1) end, { 'i', 's'}),
          ['<C-p>'] = cmp.mapping(function() luasnip.jump(-1) end, { 'i', 's'}),
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
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer', max_items = 10 },
          { name = 'path' },
          { name = 'dictionary', keyword_length = 2, max_items = 10, },
        },
      }
    end
  },
})




-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
--  Add any additional override configuration in the following tables. They will be passed to
--  the `settings` field of the server config. You must look up that documentation yourself.



