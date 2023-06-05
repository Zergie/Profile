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
--require('user.lspconfig')
require('user.keymaps')
require('user.autocmd')



require("lazy").setup({
  { -- Theme inspired by Atom
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
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
      end

      map("n", "<Leader>l", "<cmd>0Gclog -- %<cr>", "git log [Fugitive]")
      map("n", "[q",        "<cmd>cprev<cr>",       "Prev qf item")
      map("n", "]q",        "<cmd>cnext<cr>",       "Next qf item")
      map("n", "[Q",        "<cmd>cfirst<cr>",      "First qf item")
      map("n", "]Q",        "<cmd>clast<cr>",       "Last qf item")
    end
  },

  { -- File Explorer For Neovim Written In Lua
    'nvim-tree/nvim-tree.lua',
    config = function ()
      -- disable netrw at the very start of your init.lua
      vim.g.loaded_netrw = 1
      vim.g.loaded_netrwPlugin = 1

      -- set termguicolors to enable highlight groups
      vim.opt.termguicolors = true

      -- empty setup using defaults
      require("nvim-tree").setup()

      vim.keymap.set('n', '<Leader>x', '<cmd>NvimTreeToggle<cr>', { noremap = true, silent = true, desc = "File Explorer" })
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
        vim.keymap.set("", lhs, rhs, { noremap = true, silent = true, desc = desc })
      end
      local hop = require("hop")
      local hint = require("hop.hint")
      local directions = hint.HintDirection

      hop.setup()
      map("<Leader>f", function() hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true }) end, "Hop forward find")
      map("<Leader>F", function() hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true }) end, "Hop backward find")
      map("<Leader>t", function() hop.hint_char1({ direction = directions.AFTER_CURSOR, current_line_only = true, hint_offset = -1 }) end, "Hop forward till")
      map("<Leader>T", function() hop.hint_char1({ direction = directions.BEFORE_CURSOR, current_line_only = true, hint_offset = 1 }) end, "Hop backward till")
      map("<Leader>w", function () hop.hint_words{ } end, "Hop word")
      map("<Leader>j", function () hop.hint_lines{ } end, "Hop word")
      map("s",         function () hop.hint_char2{ } end, "Hop 2chars forward")
      map("<Leader>w", function () hop.hint_words{ } end, "Hop word")
      map("<Leader>j", function () hop.hint_lines{ } end, "Hop word")
      map("s",         function () hop.hint_char2{ } end, "Hop 2chars forward")
    end,
  },

  { -- inline key help
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

  { -- allows align e.g. vipga=
    'junegunn/vim-easy-align',
    config = function ()
      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc .. "[EasyAlign]" })
      end
      map("x", "ga", "<Plug>(EasyAlign)", "Align")
      map("n", "ga", "<Plug>(EasyAlign)", "Align")
    end
  },

  'mracos/mermaid.vim', -- mermaid diagram

  { -- floating terminal for compling
    -- 'voldikss/vim-floaterm',
    'numToStr/FTerm.nvim',
    config = function ()
      local fterm = require('FTerm')
      fterm.setup{
        cmd = "pwsh",
      }

      local map = function (mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
      end
      map("n", "<C-k>", fterm.toggle, "Toggle Terminal")
      map("t", "<C-k>", fterm.toggle, "Toggle Terminal")
    end
  },

  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim'
    },
    config = function ()
      -- See `:help telescope` and `:help telescope.setup()`
      require('telescope').setup {
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
    end
  },


  { -- Add indentation guides even on blank lines
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


  { -- LSP Configuration & Plugins
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
                  on_attach = on_attach,
                  settings = servers[server_name],
                }
              end,
            }
          end
        end
      },

      { -- Useful status updates for LSP
        'j-hui/fidget.nvim',
        config = function ()
          require('fidget').setup()
        end
      },

      -- A Neovim Lua plugin providing access to the SchemaStore catalog.
      'b0o/schemastore.nvim',
    },
  },

  { -- Autocompletion
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



-- LSP settings.
--  This function gets run when an LSP connects to a particular buffer.
local on_attach = function(client, bufnr)
  -- NOTE: Remember that lua is a real programming language, and as such it is possible
  -- to define small helper and utility functions so you don't have to repeat yourself
  -- many times.
  --
  -- In this case, we create a function that lets us more easily define mappings specific
  -- for LSP related items. It sets the mode, buffer and description for us each time.
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  if client.name == "omnisharp" then
    client.server_capabilities.semanticTokensProvider = {
      full = vim.empty_dict(),
      legend = {
        tokenModifiers = { "static_symbol" },
        tokenTypes = { "comment", "excluded_code", "identifier", "keyword", "keyword_control", "number", "operator", "operator_overloaded", "preprocessor_keyword", "string", "whitespace", "text", "static_symbol", "preprocessor_text", "punctuation", "string_verbatim", "string_escape_character", "class_name", "delegate_name", "enum_name", "interface_name", "module_name", "struct_name", "type_parameter_name", "field_name", "enum_member_name", "constant_name", "local_name", "parameter_name", "method_name", "extension_method_name", "property_name", "event_name", "namespace_name", "label_name", "xml_doc_comment_attribute_name", "xml_doc_comment_attribute_quotes", "xml_doc_comment_attribute_value", "xml_doc_comment_cdata_section", "xml_doc_comment_comment", "xml_doc_comment_delimiter", "xml_doc_comment_entity_reference", "xml_doc_comment_name", "xml_doc_comment_processing_instruction", "xml_doc_comment_text", "xml_literal_attribute_name", "xml_literal_attribute_quotes", "xml_literal_attribute_value", "xml_literal_cdata_section", "xml_literal_comment", "xml_literal_delimiter", "xml_literal_embedded_expression", "xml_literal_entity_reference", "xml_literal_name", "xml_literal_processing_instruction", "xml_literal_text", "regex_comment", "regex_character_class", "regex_anchor", "regex_quantifier", "regex_grouping", "regex_alternation", "regex_text", "regex_self_escaped_character", "regex_other_escape", },
      },
      range = true,
    }
  end

  nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gd', vim.lsp.buf.definition, '[G]oto [D]efinition')
  nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  nmap('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
--  Add any additional override configuration in the following tables. They will be passed to
--  the `settings` field of the server config. You must look up that documentation yourself.



