" Functions required by ucmake.vim.
" @file ucmake.vim
" @author linuor
" @date 2018-06-17

if exists('g:cmake_has_autoloaded')
    finish
endif
let g:cmake_has_autoloaded = 1

let s:jobs = {}

function! s:set_ctx(id, key, value) abort
    if !exists("s:jobs[a:id]")
        let s:jobs[a:id] = {}
    endif
    let s:jobs[a:id][a:key] = a:value
endfunction

function! s:set_all_ctx(id) abort
    call s:set_ctx(a:id, 'source_tree_root', b:ucmake_source_tree_root)
    call s:set_ctx(a:id, 'project_name', b:ucmake_project_name)
    call s:set_ctx(a:id, 'top_cmakelists', b:ucmake_top_cmakelists)
    call s:set_ctx(a:id, 'binary_dir', b:ucmake_binary_dir)
    call s:set_ctx(a:id, 'compile_commands', b:ucmake_compile_commands)
endfunction

function! s:get_ctx(id, key) abort
    if !exists("s:jobs[a:id]")
        echoerr "uCMake: undefined id in context[" . a:id . "]"
        return
    endif
    if !exists("s:jobs[a:id][a:key]")
        echoerr "uCMake: undefined key in context[" . a:id ."][" . a:key . "]"
        return
    endif
    return s:jobs[a:id][a:key]
endfunction

function! s:normalize_cmd(lst) abort
    if has('win32') || has('win64')
        return join(a:lst)
    else
        let r = []
        for it in a:lst
            let l = strlen(it)
            if (it[0] == '"' && it[l - 1] == '"') || 
                        \(it[0] == "'" && it[l - 1] == "'")
                call add(r, it[1:-2])
            else
                call add(r, it)
            endif
        endfor
        return r
    endif
endfunction

function! s:apply_type_macro(string, type) abort
    return substitute(a:string, '{build_type}', a:type, 'g')
endfunction

function! s:make_dir(dir) abort
    let p = resolve(a:dir)
    if !isdirectory(p)
        if filereadable(p)
            echoerr 'uCMake: binary directory is a file.' .
                        \ ' Move the file and try again.'
        endif
        if exists("*mkdir")
            call mkdir(p, 'p')
        else
            echoerr 'uCMake: no mkdir(), unable to create binary directory.' .
                        \ 'Create it yourself, and try again.'
        endif
    endif
endfunction

function! s:link_compilation_database() abort
    let type = g:ucmake_active_config_types[0]
    let bindir = s:apply_type_macro(s:get_ctx(type, 'binary_dir'), type)
    let from = bindir . '/' . g:ucmake_compilation_database_name
    if !filereadable(from)
        echomsg 'uCMake: Can not find compilation database ' . from 
        return
    endif
    let target = s:apply_type_macro(s:get_ctx(type, 'compile_commands'), type)
    if isdirectory(target)
        if filereadable(target . '/' . g:ucmake_compilation_database_name)
            return
        endif
    elseif filereadable(target)
        return
    endif
    if has("win64") || has("win32")
        exec "mklink" fnameescape(from) fnameescape(target)
    else
        let cmd = "ln -s " . fnameescape(from) . " " . fnameescape(target)
        silent echo system(cmd)
    endif
endfunction

function! UcmakeFinish(job, code) abort
    for key in keys(s:jobs)
        if a:job is s:get_ctx(key, 'job')
            if g:ucmake_enable_link_compilation_database &&
                        \ key ==# g:ucmake_active_config_types[0]
                call s:link_compilation_database()
            endif
            execute 'cfile! ' . s:get_ctx(key, 'file')
            unlet s:jobs[key]
            echomsg 'uCMake: finish job with type of "' . key . '"'
        endif
    endfor
endfunction

function! s:cmake_config(args) abort
    if len(s:jobs) > 0
        echomsg 'uCMake: CMake is still running, please wait.'
        return
    endif
    let prg = ['"' . g:ucmake_cmake_prg . '"']
    for key in keys(g:ucmake_cache_entries)
        let prg += ['"-D' . key . '=' . g:ucmake_cache_entries[key] . '"']
    endfor
    for typ in g:ucmake_active_config_types
        let cm = deepcopy(prg)
        if typ !=# ''
            let cm += ["'-DCMAKE_BUILD_TYPE:String=" . typ . "'"]
        endif
        if g:ucmake_enable_link_compilation_database !=# ''
            let cm += ["'-DCMAKE_EXPORT_COMPILE_COMMANDS:Bool=" .
                        \ g:ucmake_enable_link_compilation_database . "'"]
        endif
        if a:args !=# ''
            let cm += split(a:args)
        endif
        let cm += [ '"' . b:ucmake_top_cmakelists . '"']
        let bindir = s:apply_type_macro(b:ucmake_binary_dir, typ)
        call s:make_dir(bindir)
        let cm += ['"-B' . bindir . '"']
        let outfile = tempname()
        call s:set_all_ctx(typ)
        let s:jobs[typ]['file'] = outfile
        let cm = s:normalize_cmd(cm)
        let s:jobs[typ]['job'] = job_start(cm, {'exit_cb': 'UcmakeFinish',
                    \ 'out_io': 'file',
                    \ 'err_io': 'out', 'out_name': outfile,
                    \ 'cwd': bindir})
        echomsg 'uCMake: generating with type of "'. typ . '" ...'
    endfor
endfunction

function! s:cmake_compile(args) abort
    if len(s:jobs) > 0
        echomsg 'uCMake: CMake is still running, please wait.'
        return
    endif
    for typ in g:ucmake_active_config_types
        let prg = ['"' . g:ucmake_cmake_prg . '"']
        let bindir = s:apply_type_macro(b:ucmake_binary_dir, typ)
        let prg += ["--build" , '"' . bindir . '"']
        if a:args !=# ''
            let prg += ["--"]
            let prg += split(a:args)
        endif
        let outfile = tempname()
        call s:set_all_ctx(typ)
        let s:jobs[typ]['file'] = outfile
        let prg = s:normalize_cmd(prg)
        let s:jobs[typ]['job'] = job_start(prg, {'exit_cb': 'UcmakeFinish',
                    \ 'out_io': 'file',
                    \ 'err_io': 'out', 'out_name': outfile,
                    \ 'cwd': bindir})
        echomsg 'uCMake: compling with type of "'. typ . '"...'
    endfor
endfunction

function! s:setup_commands() abort
    command! -nargs=* -buffer Cmake :call s:cmake_config(<q-args>)
    command! -nargs=* -buffer Amake :call s:cmake_compile(<q-args>)
    let bindir =s:apply_type_macro(b:ucmake_binary_dir,
                \ g:ucmake_active_config_types[0])
    let &makeprg = g:ucmake_cmake_prg . ' --build ' . bindir
endfunction

function! ucmake#Init(path) abort
    call s:setup_commands()
endfunction

