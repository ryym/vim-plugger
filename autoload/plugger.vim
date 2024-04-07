" My plugin manager
"
" - One configuration file for one plugin
"     - It makes plugin management easy and scalable rather than
"       putting all plugin configurations together in a single file.
" - Allow to define before/after load hook
"     - It is important that we can define them in a one place per plugin.
" - Use Vim's package system
"     - Put all plugins in the '/opt' directory for easy enabling/disabling.

let s:conf = {
  \   'pack_root': '',
  \   'conf_root': '',
  \   'autoload_prefix': '',
  \   'is_debug': 0,
  \   'tmp_skip': [],
  \   'lua_require_prefix': '',
  \ }

let s:repo_root = expand('<sfile>:p:h:h')

let s:load_state = {
  \   'not_loaded': 0,
  \   'loaded': 1,
  \   'skipped': 2,
  \   'unmet_deps': 3,
  \ }

function! plugger#enable(conf) abort
  call plugger#setup(a:conf)
  call plugger#load_plugins()
endfunction

function! plugger#setup(conf) abort
  " Default value.
  let first_packpath = split(&packpath, ',')[0]
  let s:conf.pack_root = first_packpath . '/pack/plugs/opt/'

  for key in keys(s:conf)
    if has_key(a:conf, key)
      let s:conf[key] = a:conf[key]
    endif
  endfor

  command! -nargs=+ PluggerAdd call plugger#add_conf_templates(<f-args>)
  command! PluggerInstall call plugger#install_new()
  command! -nargs=+ PluggerLoad call plugger#reload_plugins(<f-args>)
  command! -nargs=+ PluggerUpdate call plugger#update(<f-args>)
  command! -nargs=+ PluggerRemove call plugger#remove_configs(<f-args>)
  command! -nargs=+ PluggerUninstall call plugger#uninstall(<f-args>)

  augroup plugger
    autocmd!

    autocmd User plugger_async_load_post :
  augroup END
endfunction

" Load all plugin configurations and load plugins.
" This ignores not installed plugins.
function! plugger#load_plugins() abort
  let plugs = s:load_configs()

  let startup_file = len(argv()) == 0 ? 0 : argv()[0]
  let key_groups = s:classify_plug_keys(plugs, startup_file)

  call s:load_plugins(key_groups[0], plugs)
  call timer_start(1, {-> s:load_plugins_async(key_groups[1], plugs)})
endfunction

function! s:load_plugins_async(keys, plugs) abort
  call s:load_plugins(a:keys, a:plugs)
  doautocmd User plugger_async_load_post
endfunction

function! s:load_plugins(keys, plugs) abort
  for key in a:keys
    let conf = a:plugs.confs[key]
    if conf.installed
      call s:load_plugin(key, a:plugs, 0)
    endif
  endfor
endfunction

function! s:classify_plug_keys(plugs, startup_file) abort
  let sync_keys = []
  let async_keys = []
  for key in a:plugs.keys
    let conf = a:plugs.confs[key]

    " For async loading, we need to consider the case when a user launches Vim
    " with a filename. For example when a user opens a Elm file by 'vim Foo.elm',
    " the `Foo.elm` file does not be highlighted even if `elm.vim` is installed
    " because the plugin is loaded asynchronously (that is, loaded after the file is loaded).
    " We can avoid such cases by detecting the file names and load synchronously as needed.
    if conf.async.enabled && (a:startup_file is 0 || !conf.async.detect_startup_file(a:startup_file))
      call add(async_keys, key)
    else
      call add(sync_keys, key)
    endif
  endfor
  return [sync_keys, async_keys]
endfunction

function! s:initial_conf() abort
  return {
    \   'repo': '',
    \   'depends': [],
    \   'install_if': 1,
    \   'skip_load': 0,
    \   'async': { 'enabled': 1, 'detect_startup_file': 0 },
    \   'installed': 0,
    \   'load_state': s:load_state.not_loaded,
    \ }
endfunction

" Install configured but not installed plugins.
function! plugger#install_new() abort
  let plugs = s:load_configs()

  let keys_not_installed = []
  for key in plugs.keys
    let conf = plugs.confs[key]
    if !conf.installed && conf.install_if
      call add(keys_not_installed, key)
    endif
  endfor

  if len(keys_not_installed) == 0
    echom 'All plugins are installed already'
    return
  endif

  call s:update_plugins(keys_not_installed, plugs)
endfunction

function! plugger#update(...) abort
  let plugs = s:load_configs()
  call s:update_plugins(a:000, plugs)
endfunction

function! s:update_plugins(keys, plugs) abort
  if len(a:keys) == 0
    return
  endif

  let repos = []
  for key in a:keys
    if !has_key(a:plugs.confs, key)
      throw '[plugger] unknown plugin' key
    endif
    let conf = a:plugs.confs[key]
    call add(repos, {'name': key, 'url': conf.repo})
  endfor

  " Note that we need to handle some differences between Vim and Neovim around job execution.
  "   - They provide similar but different functions
  "     - Vim ... job_start
  "     - Neovim ... jobstart
  "   - The output format passed to stdout/stderr callbacks are different
  "     - Vim ... Called for each line of stdout, so `a:out` is a string.
  "     - Neovim ... Called with multiple output lines, so `a:out` is an array.

  let ctx = {'plugs': a:plugs, 'repos': repos, 'errs': {}}

  function ctx.on_stdout(_ch, out, ...) abort
    if type(a:out) ==# type([])
      for m in a:out
        if strlen(m) > 0
          echom m
        endif
      endfor
    else
      echom out
    endif
  endfunction

  function ctx.on_stderr(_ch, out, ...) abort
    " I don't know why but Neovim calls on_stderr with [''] even if there are no stderrs.
    if type(a:out) ==# type([]) && a:out[0] ==# ''
      return
    endif

    if len(self.errs) > 0
      echohl ErrorMsg
      echom string(self.errs)
      echom string(a:out)
      echom 'stderr callbacks called multiple times unexpectedly'
      echohl None
      return
    endif

    if type(a:out) ==# type([])
      let out = join(a:out, ' ')
    else
      let out = a:out
    endif

    try
      let errs = json_decode(out)
      let self.errs.plugins = errs
    catch
      let self.errs = {'message': out}
    endtry
  endfunction

  function ctx.on_exit(...) abort
    if len(self.errs) == 0
      echom len(self.repos) 'plugins have been installed'
    else
      echohl ErrorMsg
      if has_key(self.errs, 'plugins')
        for key in keys(self.errs.plugins)
          echom '[plugger]: FAIL ' . key . ' ' . self.errs.plugins[key].message
        endfor
        echom len(self.errs) 'installations have failed (see messages)'
      else
        echom '[plugger]: Unexpected error: ' . self.errs.message
      endif
      echohl None
    endif

    let installed_keys = []
    for repo in self.repos
      if !has_key(self.errs, repo.name)
        let self.plugs.confs[repo.name].installed = 1
        call add(installed_keys, repo.name)
      endif
    endfor

    call s:load_plugins(installed_keys, self.plugs)
  endfunction

  if !isdirectory(s:conf.pack_root)
    call mkdir(s:conf.pack_root, 'p')
  endif

  echom 'Installing ' . len(repos) . ' plugins...'
  let arg = {
    \   'root_dir': s:conf.pack_root,
    \   'is_debug': s:conf.is_debug,
    \   'plugins': repos,
    \ }

  let install_script = s:repo_root . '/scripts/install-plugins'
  if has('nvim')
    call jobstart([install_script, json_encode(arg)], ctx)
  else
    call job_start(
      \   [install_script, json_encode(arg)],
      \   {
      \     'out_cb': ctx.on_stdout,
      \     'err_cb': ctx.on_stderr,
      \     'close_cb': ctx.on_exit,
      \   },
      \ )
  endif
endfunction

function! plugger#plugin_path(key)
  return s:conf.pack_root . a:key
endfunction

function! s:load_configs() abort
  let conf_paths = globpath(s:conf.conf_root, '*', 0, 1)
  let plugs = {'keys': [], 'confs': {}}

  for path in conf_paths
    if isdirectory(path)
      continue
    endif

    let ext = strpart(path, len(path) - 4)
    if !(ext ==# '.vim' || ext ==# '.lua' && has('nvim'))
      continue
    endif

    let key = s:conf_name(path)

    let conf = s:initial_conf()
    let conf.installed = isdirectory(s:conf.pack_root . key)

    if ext ==# '.vim'
      call function(s:conf.autoload_prefix . key . '#configure')(conf)
    else
      let built_conf = v:lua.require(s:conf.lua_require_prefix . key).configure()
      if type(built_conf) != type({})
        throw '[plugger] configure function at ' . key . ' returned non-dictionary'
      endif
      call extend(conf, built_conf)
    endif

    if conf.repo != ''
      " Currently all plugins I use are hosted on GitHub.
      let conf.repo = 'https://github.com/' . conf.repo
    endif

    for dep in conf.depends
      if !has_key(plugs.confs, dep)
        call add(plugs.keys, dep)
        let plugs.confs[dep] = s:initial_conf()
      endif
    endfor

    if conf.async.enabled
      let tp = type(conf.async.detect_startup_file)
      if tp == v:t_number
        let conf.async.detect_startup_file = {->0}
      elseif tp == v:t_list
        let exts = conf.async.detect_startup_file
        let conf.async.detect_startup_file = function('s:has_any_ext', [exts])
      elseif tp != v:t_func
        throw '[plugger] Invalid config async.detect_startup_file:' key
      endif
    endif

    " It may be already added by another plugin which depends on it.
    if !has_key(plugs.confs, key)
      call add(plugs.keys, key)
    endif
    let plugs.confs[key] = conf
  endfor

  return plugs
endfunction

function! s:has_any_ext(exts, name) abort
  for ext in a:exts
    if matchend(a:name, '\.' . ext) != -1
      return 1
    endif
  endfor
  return 0
endfunction

function! s:conf_name(path) abort
  return fnamemodify(a:path, ':t:r')
endfunction

function! s:load_plugin(key, plugs, ignore_skip) abort
  if !has_key(a:plugs.confs, a:key)
    throw '[plugger] unknown plugin' a:key
  endif

  let conf = a:plugs.confs[a:key]
  if conf.repo == ''
    throw '[plugger] repository of ' . a:key . ' not configured'
  endif
  if !conf.installed
    throw '[plugger] cannot load ' . a:key . ' not installed yet'
  endif

  if !a:ignore_skip && (conf.skip_load || s:should_skip_tmp(a:key))
    let conf.load_state = s:load_state.skipped
    return
  endif

  let deps_ok = 1
  for dep in conf.depends
    if a:plugs.confs[dep].load_state != s:load_state.loaded && !s:is_already_loaded(dep)
      let deps_ok = 0
      break
    endif
  endfor
  if !deps_ok
    let conf.load_state = s:load_state.unmet_deps
    echom '[plugger] ' . a:key . ' has not loaded dependency: ' . dep
    return
  endif

  if has_key(conf, 'before_load')
    call conf.before_load()
  endif

  execute 'packadd' a:key
  let doc_dir = s:conf.pack_root . '/' . a:key . '/doc'
  if isdirectory(doc_dir)
    execute 'helptags' doc_dir
  endif

  let after_plugin_dir = s:conf.pack_root . a:key . '/after/plugin'
  if isdirectory(after_plugin_dir)
    let paths = s:list_runnable_files_rec(after_plugin_dir, [])
    for path in paths
      execute 'source' path
    endfor
  endif

  if has_key(conf, 'after_load')
    call conf.after_load()
  endif

  let conf.load_state = s:load_state.loaded
endfunction

function! s:is_already_loaded(key)
  let paths = split(&runtimepath, ',')
  let target = s:conf.pack_root . a:key
  for path in paths
    if path ==# target
      return 1
    endif
  endfor
  return 0
endfunction

function! s:list_runnable_files_rec(dir, paths)
  let files = readdir(a:dir)
  for file in files
    let path = a:dir . '/' . file
    if isdirectory(path)
      return s:list_runnable_files_rec(path, a:paths)
    else
      let ext = strpart(path, len(path) - 4)
      if ext ==# '.vim' || ext ==# '.lua'
        call add(a:paths, path)
      endif
    endif
  endfor
  return a:paths
endfunction

function! s:should_skip_tmp(key) abort
  for key in s:conf.tmp_skip
    if key == a:key
      return 1
    endif
  endfor
  return 0
endfunction

function! plugger#add_conf_templates(...) abort
  let filepath = ''
  for cmd in a:000
    let cmds = split(cmd, ':')
    if filepath == ''
      let filepath = plugger#add_conf_template(cmds[0], join(cmds[1:], ''))
    endif
  endfor
  execute 'edit' filepath
endfunction

function! plugger#add_conf_template(name, repo) abort
  if !isdirectory(s:conf.conf_root)
    call mkdir(s:conf.conf_root, 'p')
  endif

  let filepath = s:conf.conf_root . a:name . '.vim'

  if filereadable(filepath)
    echohl ErrorMsg
    echom '[plugger]' a:name filepath 'already exists'
    echohl None
    return
  endif

  let lines = [
    \ 'function! ' . s:conf.autoload_prefix . a:name . '#configure(conf) abort',
    \ "  let a:conf.repo = '" . a:repo . "'",
    \ 'endfunction',
    \ ]
  call writefile(lines, filepath)
  return filepath
endfunction

function! plugger#reload_plugins(...) abort
  let plugs = s:load_configs()
  for key in a:000
    let path = s:determine_config_path(key)
    execute 'source' path
    call s:load_plugin(key, plugs, 1)
  endfor
endfunction

function! plugger#remove_configs(...) abort
  let paths = []
  for key in a:000
    let path = s:determine_config_path(key)
    call add(paths, path)
  endfor

  for path in paths
    call delete(path)
  endfor
endfunction

function! plugger#uninstall(...) abort
  call call(function('plugger#remove_configs'), a:000)

  for key in a:000
    let plugin_path = s:conf.pack_root . key
    if isdirectory(plugin_path)
      call delete(plugin_path, 'rf')
    endif
  endfor
endfunction

function! s:determine_config_path(key)
  let path = s:conf.conf_root . a:key . '.vim'
  if !filereadable(path)
    let path = s:conf.conf_root . a:key . '.lua'
    if !filereadable(path)
      throw '[plugger] plugin ' . a:key . ' does not exist'
    endif
  endif
  return path
endfunction
