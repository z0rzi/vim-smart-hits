
call smartHits#smartHits()

if exists('g:smartHits_should_setup_maps')
    let should_setup_maps = g:smartHits_should_setup_maps
else
    let should_setup_maps = 1
endif

if should_setup_maps
    inoremap <silent> <CR> <C-r>=smartHits#smartCR()<CR>
    inoremap <silent> <SPACE> <C-r>=smartHits#smartSpace()<CR>
    inoremap <silent> <BS> <C-r>=smartHits#smartBS()<CR>
    inoremap <silent> <C-]> <C-r>=smartHits#skip()<CR>
endif
