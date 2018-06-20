" Functions required by ucmake.vim.
" @file ucmake.vim
" @author linuor
" @date 2018-06-17

if exists('g:cmake_has_autoloaded')
    finish
endif
let g:cmake_has_autoloaded = 1

let s:step_config = "Config"
let s:step_compile = "Compile"
let s:ctx = {}

function! s:set_ctx(id, key, value) abort
    if !exists("s:ctx[a:id]")
        let s:ctx[a:id] = {}
    endif
    let s:ctx[a:id][a:key] = a:value
endfunction

function! s:set_all_ctx(id) abort
    call s:set_ctx(a:id, 'source_tree_root', b:ucmake_source_tree_root)
    call s:set_ctx(a:id, 'project_name', b:ucmake_project_name)
    call s:set_ctx(a:id, 'top_cmakelists', b:ucmake_top_cmakelists)
    call s:set_ctx(a:id, 'binary_dir', b:ucmake_binary_dir)
    call s:set_ctx(a:id, 'compile_commands', b:ucmake_compile_commands)
endfunction

function! s:get_ctx(id, key) abort
    return s:ctx[a:id][a:key]
endfunction

function! s:get_jobid(project, type) abort
    return a:project . '-' . a:type
endfunction

function! s:msg(msg, ...) abort
    echomsg 'uCmake: ' . a:msg . ' ' . join(a:000)
endfunction

function! s:error(msg, ...) abort
    echohl ErrorMsg
    echoerr 'uCmake: ' . a:msg . ' ' . join(a:000)
    echohl NONE
endfunction

function! s:warning(msg, ...) abort
    echohl WarningMsg
    echomsg 'uCmake: ' . a:msg . ' ' . join(a:000)
    echohl NONE
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
            call s:error('Binary directory is a file.',
                        \ 'Move the file and try again.')
        endif
        if exists("*mkdir")
            call mkdir(p, 'p')
        else
            call s:error('No mkdir(), unable to create binary directory.', 
                        \ 'Create it yourself, and try again.')
        endif
    endif
endfunction

function! s:link_compilation_database() abort
    let type = g:ucmake_active_config_types[0]
    let bindir = s:apply_type_macro(s:get_ctx(type, 'binary_dir'), type)
    let from = bindir . '/' . g:ucmake_compilation_database_name
    if !filereadable(from)
        call s:warning('Can not find compilation database', from)
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

function! s:callback(ch, txt) abort
    let job = ch_getjob(a:ch)
    if job == 'fail'
        return
    endif
    for key in keys(s:ctx)
        if job is s:get_ctx(key, 'job')
            let id = s:get_ctx(key, 'qfid')
            call setqflist([], 'a', {'id': id, 'items': [{'text': a:txt}]})
            break
        endif
    endfor
endfunction

function! s:exit_cb(job, code) abort
    for key in keys(s:ctx)
        if a:job is s:get_ctx(key, 'job')
            let step = s:get_ctx(key, 'step')
            if step ==# s:step_config &&
                        \ g:ucmake_enable_link_compilation_database &&
                        \ key ==# g:ucmake_active_config_types[0]
                call s:link_compilation_database()
            endif
            copen
            unlet s:ctx[key]
            call s:msg('Finish job', key, step)
        endif
    endfor
endfunction

function! ucmake#CmakeConfig(args) abort
    let prg = ['"' . g:ucmake_cmake_prg . '"']
    for key in keys(g:ucmake_cache_entries)
        let prg += ['"-D' . key . '=' . g:ucmake_cache_entries[key] . '"']
    endfor
    for typ in g:ucmake_active_config_types
        let job_id = s:get_jobid(b:ucmake_project_name, typ)
        if exists("s:ctx[job_id]")
            call s:warning('CMake is still running for', b:ucmake_project_name,
                        \ 'with type of "' . typ . '", please wait.')
            return
        endif
        call s:set_ctx(job_id, 'step', s:step_config)
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
        let cm = s:normalize_cmd(cm)
        call s:set_all_ctx(job_id)
        let opt = {"callback": function('s:callback'),
                    \ "exit_cb": function('s:exit_cb'),
                    \ "in_io": "null",
                    \ "out_io": "pipe", "out_mode": "nl",
                    \ "err_io": "out", "err_mode": "nl",
                    \ "cwd": bindir}
        let j = job_start(cm, opt)
        let isfail = job_status(j)
        if isfail != 'fail'
            call setqflist([], ' ', {'title': '[uCMake]' . job_id . ': ' .
                        \ s:step_config})
            let id = getqflist({'id': 0}).id
            call s:set_ctx(job_id, 'job', j)
            call s:set_ctx(job_id, 'qfid', id)
            call s:msg('Generating', b:ucmake_project_name,
                        \ ' with type of "' . typ . '" ...')
        else
            unlet s:ctx[job_id]
        endif
    endfor
endfunction

function! ucmake#CmakeCompile(args) abort
    for typ in g:ucmake_active_config_types
        let job_id = s:get_jobid(b:ucmake_project_name, typ)
        if exists("s:ctx[job_id]")
            call s:warning('CMake is still running for', b:ucmake_project_name,
                        \ ' with type of "' . typ . '", please wait.')
            return
        endif
        call s:set_ctx(job_id, 'step', s:step_compile)
        let prg = ['"' . g:ucmake_cmake_prg . '"']
        let bindir = s:apply_type_macro(b:ucmake_binary_dir, typ)
        let prg += ["--build" , '"' . bindir . '"']
        if a:args !=# ''
            let prg += ["--"]
            let prg += split(a:args)
        endif
        let prg = s:normalize_cmd(prg)
        call s:set_all_ctx(job_id)
        let opt = {"callback": function('s:callback'),
                    \ "exit_cb": function('s:exit_cb'),
                    \ "in_io": "null",
                    \ "out_io": "pipe", "out_mode": "nl",
                    \ "err_io": "out", "err_mode": "nl",
                    \ "cwd": bindir}
        let j = job_start(prg, opt)
        let isfail = job_status(j)
        if isfail != 'fail'
            call setqflist([], ' ', {'title': '[uCMake]' . job_id . ': ' .
                        \ s:step_compile})
            let id = getqflist({'id': 0}).id
            call s:set_ctx(job_id, 'job', j)
            call s:set_ctx(job_id, 'qfid', id)
            call s:msg('Compling', b:ucmake_project_name,
                        \ 'with type of "'. typ . '"...')
        else
            unlet s:ctx[job_id]
        endif
    endfor
endfunction

