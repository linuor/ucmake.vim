" A vim helper for cmake build system.
" @file ucmake.vim
" @author linuor
" @date 2018-06-17

if exists("g:ucmake_has_loaded")
    finish
endif
if !has("file_in_path") || !has("job")
    echomsg 'uCMake: +file_in_path, +job are all required'
    finish
endif
let g:ucmake_has_loaded=1

if !exists("g:ucmake_cmake_prg") || g:ucmake_cmake_prg ==# ''
    let g:ucmake_cmake_prg = 'cmake'
endif
if !exists("g:ucmake_source_tree_root_symbolics") ||
            \ len(g:ucmake_source_tree_root_symbolics) == 0
    let g:ucmake_source_tree_root_symbolics = ['.git', 'CMakeLists.txt']
endif
if !exists("g:ucmake_cmakelists_file") || g:ucmake_cmakelists_file ==# ''
    let g:ucmake_cmakelists_file='CMakeLists.txt'
endif
if !exists("g:ucmake_active_config_types")
    let g:ucmake_active_config_types = ['Relese', 'Debug']
endif
if !exists("g:ucmake_enable_link_compilation_database")
    let g:ucmake_enable_link_compilation_database = 'ON'
endif
if !exists("g:ucmake_binary_directory")
    let g:ucmake_binary_directory = '../build_{project_name}_{build_type}'
endif
if !exists("g:ucmake_compilation_database_link_target") ||
            \ g:ucmake_compilation_database_link_target ==# ''
    let g:ucmake_compilation_database_link_target =  '{source_tree_root}'
endif
if !exists("g:ucmake_compilation_database_name") ||
            \ g:ucmake_compilation_database_name ==# ''
    let g:ucmake_compilation_database_name = 'compile_commands.json'
endif
if !exists("g:ucmake_cache_entries")
    let g:ucmake_cache_entries = {}
endif

function! s:shellslash(path) abort
  if &shell =~? 'cmd' || exists('+shellslash') && !&shellslash
    return tr(a:path, '\', '/')
  else
    return a:path
  endif
endfunction

function! s:find_symbolic(sym, path)
    let r = finddir(a:sym, a:path)
    if r !=# ''
        return r
    else
        return findfile(a:sym, a:path)
    endif
endfunction

function! s:apply_buffer_macro(string) abort
    let p = substitute(a:string, '{source_tree_root}',
                \ b:ucmake_source_tree_root, 'g')
    let p = substitute(p, '{project_name}', b:ucmake_project_name, 'g')
    return substitute(p, '{top_cmakelists}', b:ucmake_top_cmakelists, 'g')
endfunction

function! UcmakeDetect(path) abort
    let path = s:shellslash(a:path)
    if isdirectory(path)
        let path = fnamemodify(path, ':p:s?/$??')
    else
        let path = fnamemodify(path, ':p:h:s?/$??')
    endif
    let pathup = path . ';'
    let root = ''
    for s in g:ucmake_source_tree_root_symbolics
        let root = s:find_symbolic(s, pathup)
        if root !=# ''
            break
        endif
    endfor
    if root ==# ''
        return
    endif

    if root !~ '^[/\\]'
        let root = getcwd() . '/' . root
    endif
    let b:ucmake_source_tree_root = fnamemodify(root, ':p:h:h')
    let b:ucmake_project_name = fnamemodify(b:ucmake_source_tree_root, ':t')

    let top = findfile(g:ucmake_cmakelists_file,
                \ pathup . b:ucmake_source_tree_root, -1)
    if len(top) == 0
        return
    endif
    let top = top[-1]
    if top =~ '^[/\\]'
        let b:ucmake_top_cmakelists = top
    else
        let b:ucmake_top_cmakelists = getcwd() . '/' . top
    endif
    let p = ''
    if g:ucmake_binary_directory =~ '^[/\\]'
        let p = simplify(g:ucmake_binary_directory)
    else
        let p = simplify(b:ucmake_source_tree_root . '/' .
                    \   g:ucmake_binary_directory)
    endif
    let b:ucmake_binary_dir = s:apply_buffer_macro(p)
    let b:ucmake_compile_commands =
            \ s:apply_buffer_macro(g:ucmake_compilation_database_link_target)
    return ucmake#Init(path)
endfunction

augroup ucmake
    autocmd!
    autocmd BufNewFile,BufReadPost * call UcmakeDetect(expand('%:p'))
    autocmd FileType netrw 
            \ call UcmakeDetect(fnamemodify(get(b:, 'netrw_curdir', @%), ':p'))
    autocmd VimEnter *
            \ if expand('<amatch>')==''|call UcmakeDetect(getcwd())|endif
    autocmd CmdWinEnter * call UcmakeDetect(expand('#:p'))
augroup END

