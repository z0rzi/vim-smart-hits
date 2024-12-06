
if v:version > 704 || v:version == 704 && has("patch849")
    " This allows us to repeat movement sequences using the '.' key
    let s:Right = "\<C-G>U\<RIGHT>"
    let s:Left = "\<C-G>U\<LEFT>"
else
    let s:Right = "\<RIGHT>"
    let s:Left = "\<LEFT>"
endif

if exists('g:smartHits_should_close_html_tags')
    let should_close_html_tags = g:smartHits_should_close_html_tags
else
    let should_close_html_tags = 1
endif

" Setting up the auto-closing of pairs
function! smartHits#smartHits()
    for elem in g:smartHits_pairs
        call smartHits#addAutoClose(elem[0], elem[1])
    endfor
endfunction

function s:makeRegexSafe(str)
    return escape(a:str, "\\/^$*.][~")
endfunction

function s:onSyntax(syn_name)
    let synStack = synstack(line('.'), col('.'))
    for syn in synStack
        if synIDattr(synIDtrans(syn), "name") == a:syn_name
            return 1
        endif
    endfor
    return 0
endfunction

function s:getMatchStack(lhs, rhs)
    let currentline = getline('.')

    let curpos = col('.')
    let i = 0
    let stackBefore = 0
    let stackAfter = 0
    while i < len(currentline)
        let char = currentline[i]
        let beforeCursor = i < curpos - 1

        if char == a:lhs
            if beforeCursor
                let stackBefore += 1
            else
                let stackAfter += 1
            endif
        elseif char == a:rhs
            if beforeCursor
                let stackBefore -= 1
            else
                let stackAfter -= 1
            endif
        endif

        let i += 1
    endwhile
    return [stackBefore, stackAfter]
endfunction

" Counts the occurences of the character on this line before and after the
" cursor. Doesn't count escaped characters
function s:countCharsOnLine(char, line_num, cursor_col)
    if a:line_num == 0 | let line_num = line('.') | else | let line_num = a:line_num | endif
    if a:cursor_col == 0 | let cursor_col = col('.') | else | let a:cursor_col = a:cursor_col | endif

    let cursor_col = cursor_col - 1

    let line = getline(line_num)

    let count_before = 0
    let count_after = 0

    let idx = 0

    let prev_was_escape = 0
    while idx < len(line)
        if !prev_was_escape && line[idx] == a:char
            if idx < cursor_col
                let count_before = count_before + 1
            else
                let count_after = count_after + 1
            endif
        endif
        let prev_was_escape = line[idx] == '\'
        let idx = idx + 1
    endwhile

    return [count_before, count_after]
endfunction

" Gives the abbreviations for the given filetype.
"
" Abbrevations are kind of like iab from native vim, but better.
" Are triggered when space is pressed after a given regex
"
" here are a few examples:
"
" let g:smartHits_abbrevs = {
"     \   'vim': {
"     \     'log': "echom",
"     \   },
"     \   'sh': {
"     \     'log': "echo $!",
"     \   },
"     \   'javascript': {
"     \     '^l': "let",
"     \     '^c': "const",
"     \   },
"     \   'typescript': {
"     \     '@inherit': 'javascript',
"     \     'ro': "readonly",
"     \ }
"     \}
"
" ^ at the start of lhs to only work if the match is at the start of the line
" $ at the end of lhs to only work if match is at the end of the line
" \(...\) in lhs, and $1 in rhs to repeat capture or '$&' to repeat full match
function! s:getAbbrevs(ft, already_inherited)
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
        let rhs = g:smartHits_abbrevs[ft][lhs]

        let rx = lhs
        if match(rx, '^\^')>=0 | let rx='\%(^\s*\)\@<='.rx[1:] | endif
        if match(rx, '\$$')>=0 | let rx=rx[:len(rx)-2].'\%#\s*$' | else | let rx=rx.'\%#\s*' | endif
        if match(rx, '^\w')>=0 | let rx='\<'.rx | endif
        if match(rx, '\w$')>=0 | let rx=rx.'\>' | endif
        let lhs = rx

        if len(matchstr(lhs, '^@'))
            " Inheritance
            for inherit_lang in split(rhs)
                " For all the inherited languages
                if index(a:already_inherited, inherit_lang) < 0
                    " if language is not already inherited
                    " (to avoid infinite loops)

                    call add(a:already_inherited, ft)

                    " Getting abbreviations of the other language
                    let other = s:getAbbrevs(inherit_lang, a:already_inherited)

                    " Assigning the abbrevations to this language as well
                    for _lhs in keys(other)
                        let tmp[_lhs] = other[_lhs]
                    endfor
                endif
            endfor
        else
            " Not inheritance, normal case
            let tmp[lhs] = rhs
        endif
    endfor

    let s:smartHits_cache_abbrevs[ft] = tmp
    return tmp
endfunction

" Setting up the mappings for the automatic closing of pairs
function! smartHits#addAutoClose(start, end)
    let start = escape(a:start, '"')
    let end = escape(a:end, '"')

    if a:start == a:end && len(a:start) == 1
        exe 'inoremap <silent> '.a:start[-1:].' <C-r>=smartHits#onSamePair("'.start.'")'.'")<CR>'
    else
        exe 'inoremap <silent> '.a:start[-1:].' <C-r>=smartHits#onOpenPair("'.start.'", "'.end.'", "'.escape(start[-1:], '"').'")<CR>'
    endif

    if len(a:end) == 1 && a:start != a:end
        " Mapping for the closing character, if it's only one char
        exe 'inoremap <silent> ' . a:end . ' <C-r>=smartHits#onClosePair("'.start.'", "'.end.'", "'.end.'")<CR>'
    endif
endfunction

" Called when the a pair with the same open and closing is triggered.
"
" We have to guess whether the pair is being open or closed
"
" @param char The char representing the pair
function! smartHits#onSamePair(char)
    if a:char == "'"
        if search('\w\%#', 'n')
            " It's an apostrophe right after a word, we're most likely writing
            " human language, we don't want to close the pair.
            return a:char
        endif
    endif

    let [before, after] = s:countCharsOnLine(a:char, 0, 0)
    let is_odd = (before + after) % 2
    if is_odd
        " We want to make it even, we add one char
        return a:char
    endif

    let found = s:cursorIsBetweenMatch()
    if len(found) == 0 || found[1]!=a:char
        return a:char . a:char . repeat(s:Left, len(a:char))
    endif

    return s:Right
endfunction

" Called when the a lhs of a pair is typed
"
" @param lhs The start of the pair
" @param rhs The end of the pair
" @param typed What was typed to trigger this function
function! smartHits#onOpenPair(lhs, rhs, typed)
    if len(a:lhs) == 1
        " if s:onSyntax('String') || s:onSyntax('Comment')
        "     return a:typed
        " endif

        if len(a:lhs) == 1 && len(a:rhs) == 1
            let [stackBefore, stackAfter] = s:getMatchStack(a:lhs, a:rhs)

            if stackBefore < 0 | let stackBefore = 0 | endif

            if -1 * stackAfter > stackBefore
                return a:typed
            else
                return a:lhs . a:rhs . s:Left
            endif
        endif

        return a:lhs . a:rhs . s:Left
    else
        return smartHits#autoCloseLong(a:lhs, a:rhs)
    endif
    return a:typed
endfunction

" Handles the closing of pairs when the ending is longer than 1 character
function! smartHits#autoCloseLong(start, end)
    if search( s:makeRegexSafe(a:start[:-2]) . '\%#\(\s*' . s:makeRegexSafe(a:end) . '\)\@!', 'n')
        " If the cursor is not already followed by the ending, we add the
        " ending, and reposition the cursor
        return a:start[-1:] . a:end . repeat(s:Left, len(a:end))
    endif
    " Otherwise, we just enter the last character
    return a:start[-1:]
endfunction


" Returns the closing tag for the current HTML tag
function! s:closeHTMLTag()
    let line = getline('.')
    let col = col('.')
    
    " Search for the opening tag before cursor
    let tag_match = matchstr(line, '<\zs[a-zA-Z\-_0-9]\+\ze\s*>\?$')
    
    if empty(tag_match)
        return ''
    endif
    
    " Check if we're already in a closing tag
    if line[col-2] == '/'
        return ''
    endif
    
    " Check for self-closing tags
    let self_closing_tags = ['img', 'br', 'hr', 'input', 'meta', 'link', 'area', 'base', 'col', 'command', 'embed', 'keygen', 'param', 'source', 'track', 'wbr']
    if index(self_closing_tags, tag_match) >= 0
        return ''
    endif
    
    " Add the closing tag
    return '</' . tag_match . '>' . repeat(s:Left, len(tag_match) + 3)
endfunction

" Called when the a rhs of a pair is typed
"
" @param lhs The start of the pair
" @param rhs The end of the pair
" @param typed What was typed to trigger this function
function! smartHits#onClosePair(lhs, rhs, typed)
    let nextchar =  getline('.')[col('.') - 1]

    let suffix = ''

    if &ft == 'html' && a:rhs == '>' && should_close_html_tags
        let suffix = s:closeHTMLTag()
    endif

    if nextchar == a:rhs
        " If the next char is the same as the closing char,
        " we just move the cursor
        let [stackBefore, stackAfter] = s:getMatchStack(a:lhs, a:rhs)

        if stackAfter > 0 | let stackAfter = 0 | endif

        if stackAfter + stackBefore > 0
            return a:typed . suffix
        else
            " Using <del>typed instead of just <right> because there might be
            " a mapping on the typed char, and we want to trigger it
            return "\<DEL>" . a:typed . suffix
        endif
    endif

    let found = s:cursorIsBetweenMatch()
    if len(found) == 0 || found[1]!=a:rhs | return a:typed . suffix | endif
    return s:Right . suffix
endfunction

" Checks if the cursor is directly between a pair
" @return {[string, string]|[]} The start and end pattern if found, an
"                               empty array otherwise
function! s:cursorIsBetweenMatch()
    for [beg, end] in g:smartHits_pairs
        if search( s:makeRegexSafe(beg) . '\%#' . s:makeRegexSafe(end), 'n')
            return [beg, end]
        endif
    endfor
    return []
endfunction

" Handles the return key (<CR>)
"
" Adds 2 returns if the cursor is between a pair
"    eg:
"       (|)
"      becomes
"       (
"         |
"       )
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

" Handles the space key.
"
" Adds 2 spaces if the cursor is between a pair.
"   (|) => ( | )
"
" Also handles the expansion of abbreviations.
function! smartHits#smartSpace()
    let abbrevs = s:getAbbrevs('', [])
    for lhs in keys(abbrevs)
        let rx = lhs

        let [line, col, sub] = searchpos(rx, 'nbp')
        if line
            let rhs = abbrevs[lhs]
            let cnt = 10
            let matched = getline(line)[col-1:col('.')-2]
            while match(rhs, '\$\%(\d\+\|&\)') >= 0
                " There is a replace string in rhs, we will have to insert
                " content from the matched string
                if cnt < 0 | break | endif
                let cnt -= 1
                let num = matchstr(rhs, '\$\zs\%(\d\+\|&\)')
                if num != '&' | let num = '\'.num | endif

                " Taking the cursor indicator ('\%#') out of lhs
                let lhs = substitute(lhs, '\\%#', '', '')

                " We find the substring
                let found = substitute(matched, lhs, num, '')

                " We substitute the matched string in the rhs
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

    if len(s:cursorIsBetweenMatch())
        return "\<SPACE>\<SPACE>" . s:Left
    endif


    return "\<SPACE>"
endfunction

" Handles the backspace key.
"
" Removes pairs with one backspace if cursor is between them.
"
" Removes the whole line with indent if cursor is in the middle of nowhere
function! smartHits#smartBS()
    if col('.') == 1
        return "\<BS>"
    endif

    for [start, end] in g:smartHits_pairs
        " Checking if the cursor is between 2 pairs, with white characters in between

        let rx = s:makeRegexSafe(start).'\s*\(\n\|\s\)\s*\%#\s*\n\?\s*'.s:makeRegexSafe(end)
        let [line, col] = searchpos(rx, 'n')
        if line
            " The regex was found, the cursor is in between a pair, with
            " white chars in between
            let offset = col + len(start)

            " We remove the white chars
            exe '%s/' . rx . '/' . s:makeRegexSafe(start) . s:makeRegexSafe(end) . '/'

            " We reposition the cursor
            call cursor(0, offset)

            return ''
        endif
    endfor

    let match = s:cursorIsBetweenMatch()
    if len(match) > 0
        " The cursor is between 2 pairs
        let [beg, end] = match

        if beg == end && len(beg) == 1
            let [before, after] = s:countCharsOnLine(beg, 0, 0)
            let is_odd = (before + after) % 2

            if is_odd
                " We try to make the number even
                return "\<BS>"
            endif

        elseif len(end) == 1 && len(beg) == 1
            let [stackBefore, stackAfter] = s:getMatchStack(beg, end)

            if stackBefore < 0 | let stackBefore = 0 | endif

            if stackAfter + stackBefore > 0
                return "\<BS>"
            else
                return "\<BS>\<DEL>"
            endif
        endif


        if len(beg) > 1
            " The start is long, we don't support these cases, because
            " removing everything can seem counter-intuitive in some cases
            return "\<BS>"

            " To support it, replace the return by the following line:
            " return repeat("\<BS>", len(beg)) . repeat("\<DEL>", len(end))
        endif

        return "\<BS>" . repeat("\<DEL>", len(end))
    endif

    " It seems to be just a normal backspace, no pairs invloved

    if search('^\s\+\%#', 'n')
        " If we're in the middle of nowhere with indent, we remove the indent
        return "\<C-u>"
    endif

    return "\<BS>"
endfunction

" Pushes the character at the end of the line
function! smartHits#sendToEol()
    if col('.') == col('$') - 1
        let eol = 1
    else
        let eol = 0
    endif
    norm!"ax
    let cara = @a
    let lineContent = getline('.')
    let lastChar = lineContent[-1:]

    if lastChar == ';'
        let new_col = col('$') - 1
    else
        let new_col = col('$')
    endif

    call setpos('.', [0, line('.'), new_col, 0])

    return cara
endfunction

" Pushes the character right after the cursor further on the line.
" Especially useful to enclose existing code in brackets
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

" Pushes the character before the cursor backwards.
" Not really useful :D
function! smartHits#unskip()
    if !exists('b:__carcol') || b:__carcol < 0 || b:__curpos[0] != line('.') || b:__curpos[1] != col('.')
        let b:__carcol = col('.')
        norm! l
    endif
    let curpos = getcurpos()
    let cara = getline('.')[b:__carcol-1]

    let l = getline('.')
    let l = l[:b:__carcol-2] . l[b:__carcol:]
    let l = l[:b:__carcol-3] . cara . l[b:__carcol-2:]
    call setline('.', l)

    let b:__curpos = [line('.'), col('.')]
    let b:__carcol = b:__carcol-1
    if b:__carcol <= 2 | let b:__carcol = -1 | endif

    call setpos('.', curpos)
    return ''
endfunction
