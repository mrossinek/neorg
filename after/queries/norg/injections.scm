((tag_name) @_tagname (tag_parameters) @language (tag_content) @content (#eq? @_tagname "code"))

; Custom injections for language shorthands
((tag_name) @_tagname (tag_parameters) @_language (tag_content) @content (#eq? @_language "js") (#set! "language" "javascript"))
