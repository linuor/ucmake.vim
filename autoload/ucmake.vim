" Functions required by ucmake.vim.
" @file ucmake.vim
" @author linuor
" @date 2018-06-17

if exists('g:cmake_has_autoloaded')
    finish
endif
let g:cmake_has_autoloaded = 1

let s:phase_config = "Config"
let s:phase_compile = "Compile"
let s:ctx = {}

function! s:apply_type_macro(string, type) abort
    return substitute(a:string, '{build_type}', a:type, 'g')
endfunction

function! s:set_ctx(id, key, value) abort
    if !exists("s:ctx[a:id]")
        let s:ctx[a:id] = {}
    endif
    let s:ctx[a:id][a:key] = a:value
endfunction

function! s:set_buffer_ctx(id, typ) abort
    call s:set_ctx(a:id, 'source_tree_root', b:ucmake_source_tree_root)
    call s:set_ctx(a:id, 'project_name', b:ucmake_project_name)
    call s:set_ctx(a:id, 'top_cmakelists', b:ucmake_top_cmakelists)
    call s:set_ctx(a:id, 'binary_dir',
                \ s:apply_type_macro(b:ucmake_binary_dir, a:typ))
    call s:set_ctx(a:id, 'compile_commands',
                \ s:apply_type_macro(b:ucmake_compile_commands, a:typ))
endfunction

function! s:get_ctx(id, key) abort
    return s:ctx[a:id][a:key]
endfunction

function! s:get_jobid(project, type) abort
    return a:project . '(' . a:type .')'
endfunction

" TODO remove, unused
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
    if has('win32')
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

function! s:link_compilation_database(id, bindir) abort
    let from = a:bindir . '/' . g:ucmake_compilation_database_name
    if !filereadable(from)
        call s:warning('Can not find compilation database', from)
        return
    endif
    let target = s:get_ctx(a:id, 'compile_commands')
    if isdirectory(target)
        if filereadable(target . '/' . g:ucmake_compilation_database_name)
            return
        endif
    elseif filereadable(target)
        return
    endif
    if has("win32")
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
            call setqflist([], 'a', {'id': id, 'lines': [a:txt]})
            cbottom
            break
        endif
    endfor
endfunction

function! s:exit_cb(job, code) abort
    let index=0
    for key in keys(s:ctx)
        let index += 1
        if a:job is s:get_ctx(key, 'job')
            let phase = s:get_ctx(key, 'phase')
            if phase ==# s:phase_config &&
                        \ g:ucmake_enable_link_compilation_database ==? 'ON'  &&
                        \ index == 1
                call s:link_compilation_database(key,
                            \ s:get_ctx(key, 'binary_dir'))
            endif
            call setqflist([], 'a', {'id': s:get_ctx(key, 'qfid'), 'items':
                        \ [{'text': 'Job exited with code ' . a:code}]})
            cbottom
            unlet s:ctx[key]
            break
        endif
    endfor
endfunction

function! s:run(job_id, typ, prg, phase, cwd) abort
    let cm = s:normalize_cmd(a:prg)
    call s:set_buffer_ctx(a:job_id, a:typ)
    call s:set_ctx(a:job_id, 'phase', a:phase)
    let opt = {"callback": function('s:callback'),
                \ "exit_cb": function('s:exit_cb'),
                \ "in_io": "null",
                \ "out_io": "pipe", "out_mode": "nl",
                \ "err_io": "out", "err_mode": "nl",
                \ "cwd": a:cwd}
    call setqflist([], ' ', {'title': '[uCMake]' . a:job_id . ': ' .
                \ a:phase})
    let id = getqflist({'id': 0}).id
    call s:set_ctx(a:job_id, 'qfid', id)
    if (g:ucmake_open_quickfix_window)
        copen
    endif
    call setqflist([{'text':
        \ a:phase .' '. a:job_id . ' ...'}, {'text': join(deepcopy(cm))}], 'a')
    let j = job_start(cm, opt)
    let isfail = job_status(j)
    if isfail != 'fail'
        call s:set_ctx(a:job_id, 'job', j)
    else
        call setqflist([], 'a', {'id':id, {'items':
                    \ [{'text': 'Fail to start job.'}]}})
        unlet s:ctx[a:job_id]
    endif
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
            continue
        endif
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
        call s:run(job_id, typ, cm, s:phase_config, bindir)
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
        let prg = ['"' . g:ucmake_cmake_prg . '"']
        let bindir = s:apply_type_macro(b:ucmake_binary_dir, typ)
        let prg += ["--build" , '"' . bindir . '"']
        if a:args !=# ''
            let prg += ["--"]
            let prg += split(a:args)
        endif
        call s:run(job_id, typ, prg, s:phase_compile, bindir)
    endfor
endfunction

