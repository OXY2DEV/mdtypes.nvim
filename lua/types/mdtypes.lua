---@meta


---@class mdtyles.cache.buf Cached version of a parsed buffer.
---
---@field definitons mdtypes.parsed.item[] Type annotations/definitions
---@field functions mdtypes.parsed.item[] Function declarations.


---@alias mdtypes.parsed.kind
---| "funcref" Function reference(`---@param` & `---@return` block before a function).
---| "class" Class definition(`---@class`).
---| "alias" Aliased type definition(`---@alias`).
---| "function" Function declarations.


---@class mdtypes.parsed.item
---
---@field kind mdtypes.parsed.kind
---@field name string Name of `class`/`alias`/`function`.
---@field lines string[] Lines containing this parsed items(leading whitespaces are removed).


---@alias mdtypes.parsed mdtypes.parsed.item[]


---@class mdtypes.code_block Parsed code block.
---
---@field path? string File path(relative to the markdown file). May contain `$VAR` style variables.
---@field range integer[] Tree-sitter node range(`[ row_start, col_start, row_end, col_end ]`).
---@field data mdtypes.code_block.data.item[] List of data to put inside the code block.


---@class mdtypes.code_block.data.item
---
---@field kind mdtypes.parsed.kind | "eval" Type of data to insert.
---@field value string

