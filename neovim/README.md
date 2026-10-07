# Startup performance

The configuration uses lazy.nvim with explicit loading triggers. The colorscheme loads
immediately; which-key and lualine load on `VeryLazy`. Telescope, nvim-tree, FTerm,
Fugitive, EasyAlign, Translate and ChatGPT load through their commands, mappings or Lua
modules. Opening a directory still opens nvim-tree automatically.

Context, indentation guides and indentation detection load when a file is opened.
LSP/Mason load for the filetypes supported by the configured servers, or when an LSP/Mason
command is used. Completion and snippets load on `InsertEnter`. Search mappings registered
by LSP and VBA no longer require Telescope until the search is used. Project commands are
in `lua/user/project.lua` so filetype build mappings retain precedence when Telescope loads.

Measurements on Windows with Neovim 0.12.3 and the existing plugins, using `--headless
-i NONE --startuptime` with warm caches (October 7, 2026):

| Startup | Before | After |
| --- | ---: | ---: |
| Empty buffer | 804 ms | 179 ms |
| Lua file | 1,092 ms | 630 ms |
| VBA file (`.ACM`) | 1,055 ms | 276 ms |

Values are medians: five runs for the empty buffer and final measurements, three for
the original file starts. These measure the first screen; the headless measurements
exclude `VeryLazy` UI work. A regular terminal start also completed successfully at
195 ms. Loading a feature for the first time now pays its setup cost at that point.

Run the repeatable measurement from the repository root:

```powershell
./neovim/tests/measure-startup.ps1
./neovim/tests/measure-startup.ps1 -File ./neovim/init.lua
./neovim/tests/measure-startup.ps1 -MaxStartupMs 350
```

The script reports the median and keeps detailed logs in a temporary directory. The
optional budget makes excessive startup time fail the check. In a normal session,
`:Lazy profile` shows plugin loading causes and timings. See the official
[lazy-loading documentation](https://lazy.folke.io/spec/lazy_loading) and
[profiler documentation](https://lazy.folke.io/usage/profiling).

With this configuration active, run the regression check from the repository root:

```powershell
nvim --headless -i NONE "+lua dofile('neovim/tests/startup.lua')"
```

It checks that expensive plugins remain unloaded even after `VeryLazy`, then exercises
search, tree, commenting, alignment, completion and plugin setup. It neither starts a
terminal nor sends an AI/translation request. `tests/file-startup.lua` additionally checks
file/directory startup; pass a fixture as Neovim's first argument and set
`NVIM_TEST_FILETYPE` to its expected filetype for file fixtures.

# Some useful key combinations

## Auto Completion

`z=`  - Displays spelling suggestions.
`C-N` - (INSERT) Displays completions based on all words in this buffer.

## Editing

`O`             - Inserts line before cursor and starts insert.
`o`             - Inserts line after cursor and starts insert.
`gf`            - Edit existing file under cursor in same window.
`C-Wf`          - Edit existing file under cursor in split window.
`C-Wvgf`        - Edit existing file under cursor in vertically split window.
`C-Wgf`         - Edit existing file under cursor in new tabpage.
`ga=`           - Align text by =.
`gaC-X<regex>`  - Align text by <regex>.
`q<a>`          - Start recording a macro.
`q`             - End macros recording.
`@<a>`          - Execute macro.
`=`             - Ident line

## Navigation

`*`  - Go to next occurrence of word under cursor.
`#`  - Go to previous occurrence of word under cursor.
`w`  - Go to next word.
`b`  - Go to previous word.
`e`  - Go to end of word.
`gg` - Go to start of file.
`G`  - Go to end of file.

## Tabs

`gt`  - Go to next tab.
`gT`  - Go to previous tab.
`1gt` - Go to first tab.
`2gt` - Go to second tab.

## Split Windows

`C-Wl` - Go to right split window.
`C-Wh` - Go to left split window.
`C-Wj` - Go to bottom split window.
`C-Wk` - Go to top split window.

## Selections

`v`   - Enter visual mode.
`V`   - Enter visual line mode.
`o`   - (VISUAL) Switch between begin and end marker.
`vip` - Select whole paragraph.
