# vim-plugger

Yet another plugin manager for Vim and Neovim.

## Concept

### One configuration file per plugin

- You can find a plugin configuration directly from file search.
    - No need to search around a plugin name from large vimrc
- By `before_load` / `after_load` hooks, any configurations about a plugin can be placed in one file.

### Minimal feature set

- Plugins are managed by Vim's builtin [packages][vim-packages] system.
- Plugins are loaded lazily by default, by just delaying loadings a bit after Vim's startup.
    - Keep fast startup without bunch of customization of load timings (on command/key/filetype, etc)

[vim-packages]: https://vim-jp.org/vimdoc-en/repeat.html#packages

## Prerequisites

- [Node.js][nodejs] - used to install your plugins concurrently.

[nodejs]: https://nodejs.org/en/

## Getting Started

1. Install vim-plugger
2. Create configuration files as Vim autoload scripts or Lua modules
3. Run `plugger#enable`

### Install

Clone <https://github.com/ryym/vim-plugger> into your `.vim/pack`.

```
git clone https://github.com/ryym/vim-plugger /path/to/.vim/pack/init/start/vim-plugger
```

### Configure

Create configuration files per plugin as autoload scripts.
See the [Lua integration](#lua-integration) section for Lua usage.

```
autoload/
  plugin/
    cursorword.vim
    fzf.vim
```

```vim
" plugin/cursorword.vim
function! plugin#cursorword#configure(conf) abort
  let a:conf.repo = 'itchyny/vim-cursorword'
endfunction
```

```vim
" plugin/fzf.vim
function! plugin#fzf#configure(conf) abort
  let a:conf.repo = 'junegunn/fzf'
  let a:conf.install_if = executable('fzf')
  let a:conf.after_load = function('plugin#fzf#after_load')
endfunction

function! plugin#fzf#after_load()
  " ...
endfunction
```

### Run

Call `plugger#enable` to load all plugins with your configurations.

```vim
call plugger#enable({
  \   'conf_root': '/path/to/.vim/autoload/plugin/',
  \   'autoload_prefix': 'plugin#',
  \ })
```

## Lua integration

Neovim users can also use vim-plugger with Lua.

### Load plugins from Lua

```lua
-- You may need to add a path where Lua search packages in.
package.path = package.path .. ';/path/to/.vim/autoload/?.lua'

vim.api.nvim_call_function('plugger#enable', {
    {
        conf_root = '/path/to/.vim/autoload/plugin/',
        autoload_prefix = 'plugin#',
        -- You may need to define a module prefix used on `require` .
        lua_require_prefix = 'plugin.',
    },
})
```

### Configure plugins by Lua

Each plugin configuration can be written in Lua or Vim script.
In the above example, you put a Lua file in `/path/to/.vim/autoload/plugin/` .
A configuration file must return a `configure` function that builds a configuration table.
The available options is same as Vim script.

```lua
-- /path/to/.vim/autoload/plugin/foo.lua

local function configure()
  return {
      repo = 'someone/foo.nvim',
      after_load = function()
        require('foo').setup({ bar = 'baz' })
      end,
  }
end

return { configure = configure }
```

Lua configuration files are only loaded on Neovim, and ignored on Vim.

## Commands

### `PluggerInstall`

Install and load all uninstalled plugins.

### `PluggerLoad`

Load specified plugins.

```vim
:PluggerLoad easymotion fugitive
```

### `PluggerUpdate`

Reinstall and load specified plugins.

```vim
:PluggerUpdate easymotion fugitive
```

### `PluggerUninstall`

Remove specified plugins and their configuration files.

```vim
:PluggerUninstall easymotion fugitive
```

### `PluggerAdd`

Add new configuration files inside your `conf_root` without installing them.

```vim
" PluggerAdd name:owner/repo ...
:PluggerAdd emmet:mattn/emmet-vim surround:tpope/vim-surround
```

This will generate those files:

```vim
" plugin/emmet.vim
function! plugin#emmet#configure(conf) abort
  let a:conf.repo = 'mattn/emmet-vim'
endfunction
```

```vim
" plugin/surround.vim
function! plugin#surround#configure(conf) abort
  let a:conf.repo = 'tpope/vim-surround'
endfunction
```


## Plugin Configuration Options

```vim
function! plugin#example#configure(conf) abort
  " Required
  let a:conf.repo = 'ryym/example'
  
  " Optional
  let a:conf.depends = ['submode']
  let a:conf.before_load = function('plugin#example#before_load')
  let a:conf.after_load = function('plugin#example#after_load')
  let a:conf.skip_load = 0
  let a:conf.install_if = 1
  let a:conf.async.enabled = 1
  let a:conf.async.detect_startup_file = ['rb']
endfunction
```

You can customize how the plugin is loaded by modifying the `conf` dictionary passed to the `#configure` function.

### `repo` (type: String)

Specify the plugin repository as `owner/repo` format.
Currently vim-plugger only supports plugins hosted on GitHub.

### `depends` (type: List of String)

If the plugin depends on the other plugins, specify their configuration names.

```vim
" plugin/lsp.vim
function! plugin#lsp#configure(conf) abort
  let a:conf.repo = 'prabirshrestha/vim-lsp'
  let a:conf.depends = ['async']
  let a:conf.async.enabled = 0
endfunction
```

```vim
" plugin/async.vim
function! plug#async#configure(conf) abort
  let a:conf.repo = 'prabirshrestha/async.vim'
  let a:conf.async.enabled = 0
endfunction
```

Though the order in which the configuration files are loaded is undefined,
it is guaranteed that vim-plugger loads dependency plugins before the dependent.

### `before_load` / `after_load` (type: Function () -> void)

You can register callback functions called before/after a plugin is loaded.

### `skip_load` (type: Number (Boolean), default: 0)

If the value is 1, vim-plugger skips loading of that plugin at Vim's startup.
You can load the plugin later by `PluggerLoad`.

### `install_if` (type: Number (Boolean), default: 1)

If the value is 0, vim-plugger does not install the plugin.
You can use this for example to install some plugins on some specific OS or only either of Vim/NeoVim.

### `async.enabled` (type: Number (Boolean), default: 1)

If the value is 1, vim-plugger loads the plugin asynchronously.
This will prevent vim-plugger from slowing Vim's startup time, even if some plugins take a long time to initialize.

### `async.detect_startup_file` (type: List of String)

When you open a file and the file extension is in this option, the plugin is loaded synchronously even if `async.enabled` is 1.

Example:

```vim
function! plugin#jsx_pretty#configure(conf) abort
  let a:conf.repo = 'MaxMEllon/vim-jsx-pretty'
  let a:conf.async.detect_startup_file = ['js', 'jsx', 'tsx']
endfunction
```

```bash
# In those cases, jsx-pretty is loaded asynchronously.
$ vim
$ vim foo.py
$ vim bar.rs

# But is loaded synchronously in those cases.
$ vim foo.js
$ vim foo.jsx
$ vim foo.tsx
```

The reason this option exists is some plugin does not work correctly when loaded after opening a file.
Using this option, you can load a plugin before opening a file only if necessary.

## Example of Use

<https://github.com/ryym/dotfiles/tree/1a5ea9ca4dc2ece4b3bae329194902e3b88460da/dotfiles/vim/autoload/my/plug>
