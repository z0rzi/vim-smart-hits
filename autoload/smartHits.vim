
function! smartHits#smartHits()
    for elem in g:smartHits_pairs
        call smartHits#addAutoClose(elem[0], elem[1])
    endfor
endfunction

function s:makeRegexSafe(str)
    return escape(a:str, "\\/^$*.][~")
endfunction

function! s:getAbbrevs(ft, queue)
    if len(a:ft)
        let ft = a:ft
    else
        let ft = &ft
    endif

    if ! exists("g:smartHits_abbrevs['".ft."']")
        return {}
    endif

    if exists("g:smartHits_cache_abbrevs['".ft."']")
        return g:smartHits_cache_abbrevs[ft]
    endif

    let g:smartHits_cache_abbrevs = {}

    let tmp = {}
    for lhs in keys(g:smartHits_abbrevs[ft])
        let rhs = g:smartHits_abbrevs[ft][lhs]

        if len(matchstr(lhs, '^@'))
            if index(a:queue, rhs) < 0
                call add(a:queue, ft)
                let other = s:getAbbrevs(rhs, a:queue)
                for _lhs in keys(other)
                    let tmp[_lhs] = other[_lhs]
                endfor
            endif
        else
            let tmp[lhs] = rhs
        endif
    endfor

    let g:smartHits_cache_abbrevs[ft] = tmp
    return tmp
endfunction

function! smartHits#addAutoClose(start, end)

    let start = escape(a:start, '"')
    let end = escape(a:end, '"')

    if a:start == a:end && len(a:start) == 1 | let flag = -1
    else | let flag = 1 | endif
    exe 'inoremap <silent> '.a:start[-1:].' <C-r>=smartHits#autoClose("'.start.'", "'.end.'", "'.escape(start[-1:], '"').'", '.flag.')<CR>'
    " exe 'inoremap <silent> '.a:start[-1:].' <C-r>=smartHits#autoCloseLong("' . a:start . '","' . a:end . '")<CR>'

    if len(a:end) == 1 && a:start != a:end
        exe 'inoremap <silent> '.a:end.' <C-r>=smartHits#autoClose("'.start.'", "'.end.'", "'.end.'", 0)<CR>'
    endif
endfunction

function! smartHits#autoClose(start, end, typed, flag)
    if a:flag == 1
        " opening
        if len(a:start) == 1
            let synStack = synstack(line('.'), col('.'))
            for syn in synStack
                if synIDattr(synIDtrans(syn), "name") == 'String'
                    return a:typed
                endif
            endfor
            " if search('\%#' . s:makeRegexSafe(a:start), 'n')
            "     return a:typed
            " endif
            " if search('\(' . s:makeRegexSafe(a:start) . '\)\@<!\%#' . s:makeRegexSafe(a:end), 'n')
            "     return a:typed
            " endif
            return a:start.a:end."\<LEFT>"
        else
            return smartHits#autoCloseLong(a:start, a:end)
        endif
    elseif a:flag == 0
        " closing
        let found = s:cursorIsBetweenMatch()
        if len(found) == 0 || found[1]!=a:end | return a:typed | endif
        return "\<RIGHT>"
    elseif a:flag == -1
        if a:start == "'"
            if search('\w\%#', 'n')
                return a:typed
            endif
        endif
        let found = s:cursorIsBetweenMatch()
        if len(found) == 0 || found[1]!=a:end
            return a:start . a:end . repeat("\<LEFT>", len(a:end))
        endif
        return "\<RIGHT>"
    else
        return a:typed
    endif
endfunction

function! smartHits#skipClose(end)
    let found = s:cursorIsBetweenMatch()
    if len(found) == 0 | return a:end | endif

    let [foundStart, foundEnd] = found
    if foundEnd == a:end
        return "\<RIGHT>" 
    endif
    return a:end 
endfunction


function! smartHits#autoCloseLong(start, end)
    if search( s:makeRegexSafe(a:start[:-2]) . '\%#\(\s*' . s:makeRegexSafe(a:end) . '\)\@!', 'n')
        return a:start[-1:] . a:end . repeat("\<LEFT>", len(a:end))
    endif
    return a:start[-1:]
endfunction

function! s:cursorIsBetweenMatch()
    for [beg, end] in g:smartHits_pairs
        if search( s:makeRegexSafe(beg) . '\%#' . s:makeRegexSafe(end), 'n')
            return [beg, end]
        endif
    endfor
    return []
endfunction

function! smartHits#smartCR()
    let pair = s:cursorIsBetweenMatch()
    if len(pair)
        if pair[0][:1] == '/*' && pair[1][-2:] == '*/'
            s/\(\s*\).*\zs\%#/\r\1 /
            return "\<C-o>O"
        endif
        return "\<CR>\<UP>\<C-o>o"
    endif
    return "\<CR>"
endfunction

function! smartHits#smartSpace()
    if len(s:cursorIsBetweenMatch())
        return "\<SPACE>\<SPACE>\<LEFT>"
    endif

    let abbrevs = s:getAbbrevs('', [])
    for lhs in keys(abbrevs)
        let [line, col] = searchpos('\<'.lhs.'\%#', 'n')
        if line
            let rhs = abbrevs[lhs]
            exe 's/\<'.lhs.'\%#\s*//g'
            call cursor(0, col)

            if len(matchstr(rhs, '!$'))
                return rhs[:-2]
            else
                return rhs . "\<SPACE>"
            endif
        endif
    endfor

    return "\<SPACE>"
endfunction

function! smartHits#smartBS()
    for [start, end] in g:smartHits_pairs
        let [line, col] = searchpos(s:makeRegexSafe(start).'\s*\(\n\|\s\)\s*\%#\s*\n\?\s*'.s:makeRegexSafe(end), 'n')
        if line
            let offset = col + len(start)
            exe '%s/'.s:makeRegexSafe(start).'\s*\(\n\|\s\)\s*\%#\s*\n\?\s*'.s:makeRegexSafe(end).'/'.s:makeRegexSafe(start).s:makeRegexSafe(end).'/'
            call cursor(0, offset)
            return ''
        endif
    endfor

    let match = s:cursorIsBetweenMatch()
    if len(match) == 0  | return "\<BS>" | endif

    let [beg, end] = match  

    if len(beg) > 1 | return "\<BS>" | endif

    return "\<BS>" . repeat("\<DEL>", len(end))
endfunction

function! smartHits#skip()
    norm!"ax
    let cara = @a
    let next = getline('.')[col('.')-1]
    if index(['(', '[', '{'], next) != -1
        let line = line('.')
        norm!%
        if line('.') == line
            norm!"ap
            return ''
        endif
        norm!%
    endif
    if len(matchstr(next, '[a-zA-Z]'))
        norm!e"ap
    else
        if col('.') == col('$')-1
            norm!j^"aP^
        else
            norm!"ap
        endif
    endif
    return ''
endfunction
