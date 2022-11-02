local util = require 'lspconfig.util'

return {
  default_config = {
    cmd                 = { 'c:/GIT/rsvbalsp/LanguageServer.NET/DemoLanguageServer/bin/Debug/netcoreapp3.1/DemoLanguageServer.exe' },
    filetypes           = { 'vb', 'vba', 'acm', 'acf', 'acr', 'cls', 'bas' },
    root_dir            = util.find_git_ancestor,
    single_file_support = true,
  },
  docs = {
    description = [[
Language Server Protocol for VBA.
]],
    default_config = {
      root_dir = 'git root or current directory',
    },
  },
}
