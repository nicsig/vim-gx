" Interface {{{1
fu! gx#open(in_term, ...) abort "{{{2
    if a:0
        let z_save = [getreg('z'), getregtype('z')]
        norm! gv"zy
        let url = @z
        call setreg('z', z_save[0], z_save[1])
    else
        let url = s:get_url()
    endif

    if empty(url)
        return
    endif

    " [some book](~/Dropbox/ebooks/Later/Algo To Live By.pdf)
    if match(url, '^\%(https\=\|ftps\=\|www\)://') ==# -1
        " expand a possible tilde in the path to a local file
        let url = expand(url)
        if !filereadable(url)
            return
        endif
        let ext = fnamemodify(url, ':e')
        let cmd = get({'pdf': 'zathura'}, ext, 'xdg-open')
        let cmd = cmd.' '.shellescape(url).' &'
        sil call system(cmd)
    else
        if a:in_term
            " We could pass the shell command we want to execute directly to
            " `tmux split-window`, but the pane would be closed immediately.
            " Because by default, tmux closes a window/pane whose shell command
            " has completed:
            "         When the shell command completes, the window closes.
            "         See the remain-on-exit option to change this behaviour.
            "
            " For more info, see `man tmux`, and search:
            "
            "     new-window
            "     split-window
            "     respawn-pane
            "     set-remain-on-exit
            sil call system('tmux split-window -c '.$XDG_RUNTIME_VIM')
            " maximize the pane
            sil call system('tmux resize-pane -Z')
            " start `w3m`
            sil call system('tmux send-keys web \ '.shellescape(url).' Enter')
            "                                    │
            "                                    └─ without the backslash, `tmux` would think
            "                                    it's a space to separate the arguments of the
            "                                    `send-keys` command; therefore, it would remove it
            "                                    and type:
            "                                                weburl
            "                                    instead of:
            "                                                web url
            "
            "                                    The backslash is there to tell it's a semantic space.
        else
            sil call system('xdg-open '.shellescape(url))
        endif
    endif
endfu
" }}}1
" Util {{{1
fu! s:get_url() abort "{{{2
    " https://github.com/junegunn/vim-plug/wiki/extra
    if &filetype is# 'vim-plug'
        let line = getline('.')
        let sha  = matchstr(line, '^  \X*\zs\x\{7}\ze ')
        let name = empty(sha) ? matchstr(line, '^[-x+] \zs[^:]\+\ze:')
        \ : getline(search('^- .*:$', 'bn'))[2:-2]
        let uri  = get(get(g:plugs, name, {}), 'uri', '')
        if uri !~ 'github.com'
            return ''
        endif
        let repo = matchstr(uri, '[^:/]*/'.name)
        return empty(sha) ? 'https://github.com/'.repo
            \ : printf('https://github.com/%s/commit/%s', repo, sha)
    endif

    let line = getline('.')
    let pos = getcurpos()
    " [text](link)
    let pat = '\[.\{-}\]'
    let pat .= '\%((.\{-})\|\[.\{-}\]\)'
    let g = 0
    norm! 1|
    while search(pat, 'W', line('.')) && g < 100
        let col_start_link = col('.')
        norm! %l
        let col_start_url = col('.')
        norm! %
        let col_end_url = col('.')
        if pos[2] >= col_start_link && pos[2] <= col_end_url
            let url = matchstr(line, '\%'.(col_start_url+1).'c.*\%'.col_end_url.'c')
            break
        endif
        let g += 1
    endwhile
    call setpos('.', pos)

    if exists('url')
        " [text](link)
        if matchstr(line, '\%'.col_start_url.'c.') is# '('
            " This is [an example](http://example.com/ "Title") inline link.
            let url = substitute(url, '\s*".\{-}"\s*$', '', '')
            return url

        " [text][ref]
        else
            " Visit [Daring Fireball][] for more information.
            " [Daring Fireball]: http://daringfireball.net/
            if url is# ''
                let ref = matchstr(line, '\%'.(col_start_link+1).'c.*\%'.(col_start_url-1).'c')
            else
                let ref = url
            endif
            if &filetype is# 'markdown'
                let cml = ''
            else
                let cml = '\V'.matchstr(get(split(&l:cms, '%s'), 0, ''), '\S*').'\m'
            endif
            let url = filter(getline('.', '$'),
                \ {i,v -> v =~# '^\s*'.cml.'\s*\c\V['.ref.']:'})
            let url = matchstr(get(url, 0, ''), '\[.\{-}\]:\s*\zs.*')
            " [foo]: http://example.com/  "Optional Title Here"
            " [foo]: http://example.com/  'Optional Title Here'
            " [foo]: http://example.com/  (Optional Title Here)
            let pat = '\s*\(["'']\).\{-}\1\s*$'
            let pat .= '\|\s*(.\{-})\s*$'
            let url = substitute(url, pat, '', '')
            " [id]: <http://example.com/>  "Optional Title Here"
            let url = substitute(url, '^<\|>$', '', 'g')
            return url
        endif
    endif

    let url = expand('<cWORD>')
    let pat = '\%(https\=\|ftps\=\|www\)://'
    if url !~# pat
        return ''
    endif

    " Which characters make a URL invalid?
    " https://stackoverflow.com/a/13500078

    " remove everything before the first `http`, `ftp` or `www`
    let url = substitute(url, '.\{-}\ze'.pat, '', '')

    " remove everything after the first `⟩`, `>`, `)`, `]`, `}`
    " but some wikipedia links contain parentheses:{{{
    "
    "         https://en.wikipedia.org/wiki/Daemon_(computing)
    "
    " In those cases,  we need to make an exception,  and not remove the
    " text after the closing parenthesis.
    "}}}
    let chars = match(url, '(') ==# -1 ? '[⟩>)\]}]' : '[⟩>\]}]'
    let url = substitute(url, '\v.{-}\zs' . chars . '.*', '', '')

    " remove everything after the last `"`
    let url = substitute(url, '\v".*', '', '')
    return url
endfu

