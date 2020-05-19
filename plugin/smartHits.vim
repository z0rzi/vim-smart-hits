
call smartHits#smartHits()

inoremap <silent> <CR> <C-r>=smartHits#smartCR()<CR>
inoremap <silent> <SPACE> <C-r>=smartHits#smartSpace()<CR>
inoremap <silent> <BS> <C-r>=smartHits#smartBS()<CR>
inoremap <silent> <C-]> <C-r>=smartHits#skip()<CR>
