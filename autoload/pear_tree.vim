let s:pear_tree_default_rules = {
            \ 'delimiter': '',
            \ 'not_in': [],
            \ 'not_if': [],
            \ 'until': '[[:punct:][:space:]]'
            \ }
if v:version > 704 || (v:version == 704 && has('patch849'))
    let s:LEFT = "\<C-g>U" . "\<Left>"
    let s:RIGHT = "\<C-g>U" . "\<Right>"
else
    let s:LEFT = "\<Left>"
    let s:RIGHT = "\<Right>"
endif

let s:strings_to_expand = []

function! pear_tree#GenerateDelimiter(opener, wildcard, position) abort
    if !has_key(pear_tree#Pairs(), a:opener)
        return ''
    endif
    let l:not_in = pear_tree#GetRule(a:opener, 'not_in')
    if index(l:not_in, pear_tree#buffer#SyntaxRegion(a:position)) > -1
                \ || index(pear_tree#GetRule(a:opener, 'not_if'), a:wildcard) > -1
        return ''
    endif
    let l:delim = pear_tree#GetRule(a:opener, 'delimiter')
    let l:until = pear_tree#GetRule(a:opener, 'until')
    let l:index = 0
    if a:wildcard !=# ''
        let l:index = match(a:wildcard, l:until)
        if l:index == 0
            return ''
        endif
        let l:index = max([-1, l:index - 1])
    endif
    " Replace unescaped * chars with the wildcard string.
    let l:delim = join(pear_tree#string#Encode(l:delim, '*', a:wildcard[:(l:index)]), '')
    return l:delim
endfunction


function! pear_tree#IsClosingBracket(char) abort
    for l:delim_dict in values(pear_tree#Pairs())
        let l:delim = get(l:delim_dict, 'delimiter')
        if a:char ==# l:delim
            return !has_key(pear_tree#Pairs(), l:delim)
        endif
    endfor
    return 0
endfunction


function! pear_tree#IsDumbPair(char) abort
    return has_key(pear_tree#Pairs(), a:char) && pear_tree#GetRule(a:char, 'delimiter') ==# a:char
endfunction


function! pear_tree#Pairs() abort
    return get(b:, 'pear_tree_pairs', get(g:, 'pear_tree_pairs'))
endfunction


function! pear_tree#GetRule(opener, rule) abort
    let l:dict = get(pear_tree#Pairs(), a:opener)
    return get(l:dict, a:rule, s:pear_tree_default_rules[a:rule])
endfunction


function! pear_tree#HandleSimplePair(char) abort
    let l:char_after_cursor = pear_tree#cursor#CharAfter()
    let l:char_before_cursor = pear_tree#cursor#CharBefore()
    " Define situations in which Pear Tree is permitted to match.
    " If the cursor is any of the following:
    "   1. On an empty line
    "   2. At end of line and not placing dumb pair directly after a word
    "   3. Followed by whitespace and not placing dumb pair directly after a word
    "   4. Before a bracket-type character and not placing dumb pair directly after a word
    "   5. Between opening and closing pair
    " then we may match the entered character.
    if pear_tree#cursor#OnEmptyLine()
                \ || !(pear_tree#IsDumbPair(a:char) && l:char_before_cursor =~# '\w') && (pear_tree#cursor#AtEndOfLine()
                                                                                        \ || l:char_after_cursor =~# '\s'
                                                                                        \ || pear_tree#IsClosingBracket(l:char_after_cursor))
                \ || (has_key(pear_tree#Pairs(), l:char_before_cursor) && pear_tree#GetRule(l:char_before_cursor, 'delimiter') ==# l:char_after_cursor)
        let l:delim = pear_tree#GenerateDelimiter(a:char, '', pear_tree#cursor#Position())
        return l:delim . repeat(s:LEFT, pear_tree#string#VisualLength(l:delim))
    else
        return ''
    endif
endfunction


function! pear_tree#HandleComplexPair(opener, wildcard) abort
    " Define situations in which Pear Tree is permitted to match.
    " First, the wildcard string can span multiple lines, but the opener
    " should not be terminated when the terminating character is the only
    " character on the line. For example,
    "           <div
    "             class='foo'>|
    " should match, but
    "           <div
    "             class='foo'
    "           >|
    " should not match.
    " If it is the first case, the cursor should also be at the end of the
    " line, before whitespace, or between another pair.
    if strlen(pear_tree#string#Trim(pear_tree#cursor#TextBefore())) > 0
                \ && (pear_tree#cursor#AtEndOfLine()
                    \ || pear_tree#cursor#CharAfter() =~# '\s'
                    \ || pear_tree#GetSurroundingPair() != {})
        let l:delim = pear_tree#GenerateDelimiter(a:opener, a:wildcard, pear_tree#cursor#Position())
        return l:delim . repeat(s:LEFT, pear_tree#string#VisualLength(l:delim))
    else
        return ''
    endif
endfunction


function! pear_tree#OnPressDelimiter(char) abort
    if pear_tree#cursor#CharAfter() ==# a:char
        return s:RIGHT
    elseif pear_tree#IsDumbPair(a:char)
        return a:char . pear_tree#HandleSimplePair(a:char)
    else
        return a:char
    endif
endfunction


" Called when pressing the last letter in an opener string.
function! pear_tree#TerminateOpener(char) abort
    " If entered a simple (length of 1) opener and not currently typing
    " a longer strict sequence, handle the trivial pair.
    let l:traverser = pear_tree#insert_mode#GetTraverser()
    if has_key(pear_tree#Pairs(), a:char)
                \ && (l:traverser.GetString() ==# ''
                    \ || l:traverser.AtWildcard()
                    \ || !l:traverser.HasChild(l:traverser.GetCurrent(), a:char)
                    \ )
        if pear_tree#IsDumbPair(a:char)
            return pear_tree#OnPressDelimiter(a:char)
        else
            return a:char . pear_tree#HandleSimplePair(a:char)
        endif
    elseif l:traverser.StepToChild(a:char) && l:traverser.AtEndOfString()
        let l:opener = l:traverser.GetString()
        if has_key(pear_tree#Pairs(), l:opener)
            return a:char . pear_tree#HandleComplexPair(l:opener, l:traverser.GetWildcardString())
        else
            return a:char
        endif
    else
        return a:char
    endif
endfunction


function! pear_tree#GetSurroundingPair() abort
    let l:line = getline('.')
    let l:delim_trie = pear_tree#trie#New()
    for l:opener in keys(pear_tree#Pairs())
        call l:delim_trie.Insert(pear_tree#GetRule(l:opener, 'delimiter'))
    endfor
    let l:delim_trie_traverser = pear_tree#trie#Traverser(l:delim_trie)
    if l:delim_trie_traverser.WeakTraverse(l:line, col('.') - 1, col('$')) == -1
        return {}
    endif
    for [l:opener, l:delim] in items(pear_tree#Pairs())
        if l:delim['delimiter'] == l:delim_trie_traverser.GetString()
            return {'opener': l:opener,
                  \ 'delimiter': l:delim['delimiter'],
                  \ 'wildcard': l:delim_trie_traverser.GetWildcardString()}
        endif
    endfor
    return {}
endfunction


" Determine if {delim} is balanced with {opener} in the buffer. If it is,
" return the line on which the pair was determined to be balanced. Otherwise,
" return 0.
function! pear_tree#IsBalancedPair(opener, delim, wildcard, start, ...) abort
    " Initialize the stack that will be used in determining pair balance. Each
    " time an opener is found, the stack is popped. Each time a delimiter is
    " found, a dummy value is pushed onto the stack.
    let l:stack = []

    " Handle an optional argument that tells the function to ignore the first
    " {a:1} openers. This can be used to see if the delimiter after
    " the cursor will be balanced even if the previous {a:1}
    " openers were to be deleted.
    if a:0
        for l:_ in range(1, a:1)
            call add(l:stack, 0)
        endfor
    endif

    if a:wildcard !=# ''
        " Generate a hint to find openers faster when the pair contains a
        " wildcard. The {wildcard} is the wildcard string as it appears in the
        " delimiter, so it may be a trimmed version of the opener's wildcard.
        let l:opener_hint = a:opener[:pear_tree#string#UnescapedStridx(a:opener, '*', 0)]
        let l:opener_hint = join(pear_tree#string#Encode(l:opener_hint, '*', a:wildcard), '')

        let l:traverser = pear_tree#insert_mode#GetTraverser()
    endif

    let l:not_in = pear_tree#GetRule(a:opener, 'not_in')

    let l:current_position = a:start
    let l:delim_position = [l:current_position[0], l:current_position[1] + 1]
    let l:opener_position = [l:current_position[0], l:current_position[1] + 1]
    while l:current_position[0] > -1
        " Find the previous opener and delimiter in the buffer.
        if pear_tree#buffer#ComparePositions(l:opener_position, l:current_position) > 0
            if a:wildcard ==# ''
                let l:opener_position = pear_tree#buffer#ReverseSearch(a:opener, l:current_position, l:not_in)
            else
                let l:search_position = [l:current_position[0], l:current_position[1]]
                while l:search_position[0] > -1
                    let l:search_position = pear_tree#buffer#ReverseSearch(l:opener_hint, l:search_position, l:not_in)
                    let l:end_position = pear_tree#buffer#Search(a:opener[strlen(a:opener) - 1], l:search_position, l:not_in)
                    call l:traverser.Reset()
                    if l:traverser.WeakTraverseBuffer(l:search_position, l:end_position) != -1
                                \ && pear_tree#GenerateDelimiter(l:traverser.GetString(), l:traverser.GetWildcardString(), l:search_position) ==# a:delim
                        break
                    endif
                    let l:search_position[1] = l:search_position[1] - 1
                endwhile
                let l:opener_position = l:search_position
            endif
        endif
        if pear_tree#buffer#ComparePositions(l:delim_position, l:current_position) > 0
            let l:delim_position = pear_tree#buffer#ReverseSearch(a:delim, l:current_position, l:not_in)
        endif
        if l:delim_position[0] != -1
                    \ && pear_tree#buffer#ComparePositions(l:delim_position, l:opener_position) >= 0
                    \ && !(l:stack != [] && pear_tree#IsDumbPair(a:delim))
            call add(l:stack, 0)
            let l:current_position = [l:delim_position[0], l:delim_position[1] - 1]
        elseif l:opener_position[0] != -1 && l:stack != []
            call remove(l:stack, -1)
            if l:stack == []
                return a:wildcard ==# '' ? l:opener_position[0]
                                       \ : l:end_position[0]
            endif
            let l:current_position = [l:opener_position[0], l:opener_position[1] - 1]
        else
            return 0
        endif
    endwhile
endfunction


function! pear_tree#JumpOut() abort
    let l:pair = pear_tree#GetSurroundingPair()
    if l:pair == {}
        return ''
    endif
    let l:opener = l:pair['opener']
    let l:wildcard = l:pair['wildcard']
    let l:delim = pear_tree#GenerateDelimiter(l:opener, l:wildcard, pear_tree#cursor#Position())
    if l:delim ==# ''
        return ''
    endif
    if pear_tree#IsBalancedPair(l:opener, l:delim, l:wildcard, [line('.'), col('.') - 1])
        return repeat(s:RIGHT, pear_tree#string#VisualLength(l:delim))
    else
        return ''
    endif
endfunction


function! pear_tree#JumpNReturn() abort
    return pear_tree#JumpOut() . "\<CR>"
endfunction


function! pear_tree#Backspace() abort
    let l:char_before_cursor = pear_tree#cursor#CharBefore()
    if !has_key(pear_tree#Pairs(), l:char_before_cursor)
        return "\<BS>"
    endif
    let l:char_after_cursor = pear_tree#cursor#CharAfter()

    let l:not_in = pear_tree#GetRule(l:char_before_cursor, 'not_in')

    let l:next_opener = pear_tree#buffer#Search(l:char_before_cursor, [line('.'), col('.')], l:not_in)
    let l:next_delim = pear_tree#buffer#Search(l:char_after_cursor, [line('.'), col('.')], l:not_in)

    if pear_tree#GetRule(l:char_before_cursor, 'delimiter') !=# l:char_after_cursor
        let l:should_delete_both = 0
    elseif pear_tree#IsDumbPair(l:char_before_cursor)
        let l:should_delete_both = 1
    elseif get(g:, 'pear_tree_smart_backspace', 0) || get(b:, 'pear_tree_smart_backspace', 0)
        " Get the first delimiter after the cursor not preceded by an opener.
        while pear_tree#buffer#ComparePositions(l:next_opener, l:next_delim) < 0
                    \ && l:next_delim[0] != -1 && l:next_opener[0] != -1
            let l:next_delim[1] += 1
            let l:next_delim = pear_tree#buffer#Search(l:char_after_cursor, l:next_delim, l:not_in)
            let l:next_opener[1] += 1
            let l:next_opener = pear_tree#buffer#Search(l:char_before_cursor, l:next_opener, l:not_in)
        endwhile
        let l:next_delim = pear_tree#buffer#ReverseSearch(l:char_after_cursor, l:next_opener, l:not_in)
        if l:next_delim == [-1, -1]
            let l:next_delim = [line('$'), strlen(getline('$'))]
        endif
        " Will deleting both make the next delimiter unbalanced?
        let l:should_delete_both = !pear_tree#IsBalancedPair(l:char_before_cursor, l:char_after_cursor, '', l:next_delim, 1)
    else
        let l:should_delete_both = 1
    endif
    if l:should_delete_both
        return "\<Del>\<BS>"
    else
        return "\<BS>"
    endif
endfunction


function! pear_tree#PrepareExpansion() abort
    let l:pair = pear_tree#GetSurroundingPair()
    if l:pair == {}
        return "\<CR>"
    endif

    let l:opener = l:pair['opener']
    let l:wildcard = l:pair['wildcard']
    let l:delim = pear_tree#GenerateDelimiter(l:opener, l:wildcard, pear_tree#cursor#Position())

    let l:opener_line = pear_tree#IsBalancedPair(l:opener, l:delim, l:wildcard, [line('.'), col('.') - 1])

    if (l:opener_line == line('.') && (l:wildcard !=# '' || strridx(getline('.'), l:opener) == col('.') - strlen(l:opener) - 1))
        let l:text_after_cursor = pear_tree#cursor#TextAfter()
        call add(s:strings_to_expand, l:text_after_cursor)
        return repeat("\<Del>", pear_tree#string#VisualLength(l:text_after_cursor)) . "\<CR>"
    else
        return "\<CR>"
    endif
endfunction


function! pear_tree#ExpandOne() abort
    if s:strings_to_expand == []
        return ''
    endif
    return remove(s:strings_to_expand, -1)
endfunction


function! pear_tree#Expand() abort
    if s:strings_to_expand == []
        let l:ret_str = "\<Esc>"
    else
        let l:expanded_strings = join(reverse(s:strings_to_expand), "\<CR>")
        let l:ret_str = repeat(s:RIGHT, col('$') - col('.')) . "\<CR>" . l:expanded_strings . "\<Esc>"
        " Add movement back to correct position
        let l:ret_str = l:ret_str . line('.') . 'gg' . col('.') . '|lh'
        let s:strings_to_expand = []
    endif
    return l:ret_str
endfunction
