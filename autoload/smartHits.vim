
if v:version > 704 || v:version == 704 && has("patch849")
    let s:Right = "\<C-G>U\<RIGHT>"
    let s:Left = "\<C-G>U\<LEFT>"
else
    let s:Right = "\<RIGHT>"
    let s:Left = "\<LEFT>"
endif

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

    if exists("s:smartHits_cache_abbrevs['".ft."']")
        return s:smartHits_cache_abbrevs[ft]
    endif

    let s:smartHits_cache_abbrevs = {}

    let tmp = {}
    for lhs in keys(g:smartHits_abbrevs[ft])
        let rhss = g:smartHits_abbrevs[ft][lhs]

        if len(matchstr(lhs, '^@'))
            for rhs in split(rhss)
                if index(a:queue, rhs) < 0
                    call add(a:queue, ft)
                    let other = s:getAbbrevs(rhs, a:queue)
                    for _lhs in keys(other)
                        let tmp[_lhs] = other[_lhs]
                    endfor
                endif
            endfor
        else
            let tmp[lhs] = rhss
        endif
    endfor

    let s:smartHits_cache_abbrevs[ft] = tmp
    return tmp
endfunction

function! smartHits#addAutoClose(start, end)

    let start = escape(a:start, '"')
    let end = escape(a:end, '"')

    if a:start == a:end && len(a:start) == 1 | let flag = -1
    else | let flag = 1 | endif
    exe 'inoremap <silent> '.a:start[-1:].' <C-r>=smartHits#autoClose("'.start.'", "'.end.'", "'.escape(start[-1:], '"').'", '.flag.')<CR>'

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
            return a:start.a:end.s:Left
        else
            return smartHits#autoCloseLong(a:start, a:end)
        endif
    elseif a:flag == 0
        " closing
        let found = s:cursorIsBetweenMatch()
        if len(found) == 0 || found[1]!=a:end | return a:typed | endif
        return s:Right
    elseif a:flag == -1
        if a:start == "'"
            if search('\w\%#', 'n')
                return a:typed
            endif
        endif
        let found = s:cursorIsBetweenMatch()
        if len(found) == 0 || found[1]!=a:end
            return a:start . a:end . repeat(s:Left, len(a:end))
        endif
        return s:Right
    else
        return a:typed
    endif
endfunction

function! smartHits#skipClose(end)
    let found = s:cursorIsBetweenMatch()
    if len(found) == 0 | return a:end | endif

    let [foundStart, foundEnd] = found
    if foundEnd == a:end
        return s:Right
    endif
    return a:end 
endfunction


function! smartHits#autoCloseLong(start, end)
    if search( s:makeRegexSafe(a:start[:-2]) . '\%#\(\s*' . s:makeRegexSafe(a:end) . '\)\@!', 'n')
        return a:start[-1:] . a:end . repeat(s:Left, len(a:end))
    endif
    return a:start[-1:]
endfunction

function! s:cursorIsBetweenMatch()
    " Checks if the cursor is directly between a pair
    " @return {[string, string]|[]} The start and end pattern if found, an
    "                               empty array otherwise
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
        return "\<SPACE>\<SPACE>" . s:Left
    endif

    let abbrevs = s:getAbbrevs('', [])
    for lhs in keys(abbrevs)
        let rx = lhs
        if match(rx, '^\^')>=0 | let rx='\%(^\s*\)\@<='.rx[1:] | endif
        if match(rx, '\$$')>=0 | let rx=rx[:len(rx)-2].'\%#\s*$' | else | let rx=rx.'\%#\s*' | endif
        if match(rx, '^\w')>=0 | let rx='\<'.rx | endif
        if match(rx, '\w$')>=0 | let rx=rx.'\>' | endif

        let [line, col, sub] = searchpos(rx, 'nbp')
        if line
            let rhs = abbrevs[lhs]
            let cnt = 10
            let matched = getline(line)[col-1:col('.')-2]
            while match(rhs, '\$\%(\d\+\|&\)') >= 0
                if cnt < 0 | break | endif
                let cnt -= 1
                let num = matchstr(rhs, '\$\zs\%(\d\+\|&\)')
                if num != '&' | let num = '\'.num | endif
                let found = substitute(matched, lhs, num, '')
                let rhs = substitute(rhs, '\$\%(\d\+\|&\)', found, '')
            endwhile
            exe 's/'.rx.'//g'
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
    " Checking if the cursor is between 2 pairs
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
    if len(match) > 0
        let [beg, end] = match  

        if len(beg) > 1 | return "\<BS>" | endif

        return "\<BS>" . repeat("\<DEL>", len(end))
    endif

    if search('^\s\+\%#', 'n')
        return "\<C-u>\<BS>"
    endif

    return "\<BS>"
endfunction

function! smartHits#skip()
    if col('.') == col('$') - 1
        let eol = 1
    else
        let eol = 0
    endif
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
        norm!he"ap
    else
        if eol
            norm!j^"aP^
        else
            norm!"ap
        endif
    endif
    return ''
endfunction
