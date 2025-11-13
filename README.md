<!--markdoc
    {
        "generic": {
            "preserve_whitespaces": false,
            "filename": "doc/mdtypes.nvim.txt",
            "force_write": true,
            "header": {
                "desc": "👾 Auto Lua type-definition retriever for markdown",
                "tag": "mdtypes.nvim.txt"
            },
            "toc": {
                "entries": [
                    { "text": "✨ Features", "tag": "mdtypes.nvim-features" },
                    { "text": "🎇 Usage", "tag": "mdtypes.nvim-usage" },
                    { "text": "💻 API function", "tag": "mdtypes.nvim-api" },
                    { "text": "💡 Syntax", "tag": "mdtypes.nvim-syntax" }
                ]
            }
        },
        "markdown": {
            "link_url_modifiers": [
                [ "^#variables", "|mdtypes.nvim-variables|" ],
                [ "^#from", "|mdtypes.nvim-from|" ]
            ],
            "tags": {
                "Features$": [ "mdtypes.nvim-features" ],
                "Usage$": [ "mdtypes.nvim-usage" ],
                "API function$": [ "mdtypes.nvim-api" ],
                "Syntax$": [ "mdtypes.nvim-syntax" ],
                "^alias$": [ "mdtypes.nvim-syntax.alias" ],
                "^class$": [ "mdtypes.nvim-syntax.class" ],
                "^eval$": [ "mdtypes.nvim-syntax.eval" ],
                "^from$": [ "mdtypes.nvim-syntax.from" ],
                "^funcref$": [ "mdtypes.nvim-syntax.funcref" ],
                "^function$": [ "mdtypes.nvim-syntax.function" ],
                "^variables$": [ "mdtypes.nvim-syntax.variables" ]
            }
        }
    }
-->
<!--markdoc_ignore_start-->
# 👾 mdtypes.nvim

<p align="center">
    Automatic Lua type-definition & evaluated expressions generator for markdown.
</p>
<!--markdoc_ignore_end-->


https://github.com/user-attachments/assets/50c5bb84-53c9-4e44-b5b9-2d39c8e89e2e


<TOC/>

## ✨ Features

- Retrieve `class`, `alias` & `type`s from given lua file into code blocks.
- Evaluate expressions as Lua and insert returned value into code blocks.
- Retrieve `function` definitions into code blocks.
- Allows showing multiple values in a single code block.

And much more!

## 🧭 Requirements

Both of these should ship with `Neovim`,

- `tree-sitter-markdown`.
- `tree-sitter-lua`.

## 📦 Installation

### 🧩 Vim-plug

```vim
Plug "OXY2DEV/mdtypes.nvim"
```

### 💤 lazy.nvim

```lua
{
    "OXY2DEV/mdtypes.nvim",
    lazy = false
},
```

```lua
return {
    "OXY2DEV/mdtypes.nvim",
    lazy = false
};
```

### 🦠 mini.deps

```lua
local MiniDeps = require("mini.deps");

MiniDeps.add({
    source = "OXY2DEV/mdtypes.nvim",
})
```

### 🌒 rocks.nvim

>[!WARNING]
> `luarocks package` may sometimes be a bit behind `main`.

```vim
:Rocks install mdtypes.nvim
```

### 📥 GitHub release

Tagged releases can be found in the [release page](https://github.com/OXY2DEV/mdtypes.nvim/releases).

>[!NOTE]
> `Github releases` may sometimes be slightly behind `main`.

## 🎇 Usage

`mdtypes.nvim` comes with a single command.

```vim
:Types
```

This fills up code blocks in the current buffer.

### 💻 API function

You can use the provided API function in your scripts.

```lua
local buffer = vim.api.nvim_get_current_buf();
require("mdtypes").generate(buffer);
```

## 💡 Syntax

`mdtypes` makes use of info strings in code blocks. Info strings look as follows,

    ```lua Some info string
    print("hi");
    ```

The info string contains 1 or more *items* separated by a `,`. Each item represents a type of data that will be shown in the code block.

An example is given below,

    ```lua from: ./lua/types/mdtypes.lua, class: mdtypes.parsed.kind
    ```

The supported items are,

### alias

Example,

    ```lua from: ./lua/types/mdtypes.lua, alias: mdtypes.parsed.kind
    ```

Result,

```lua from: ./lua/types/mdtypes.lua, alias: mdtypes.parsed.kind
---@alias mdtypes.parsed.kind
---| "alias" Aliased type definition(`---@alias`).
---| "class" Class definition(`---@class`).
---| "funcref" Function reference(`---@param` & `---@return` block before a function).
---| "function" Function declarations.
```

Gets a type alias via it's name from the file.

### class

Example,

    ```lua from: ./lua/types/mdtypes.lua, class: mdtypes.parsed.item
    ```

Result,

```lua from: ./lua/types/mdtypes.lua, class: mdtypes.parsed.item
---@class mdtypes.parsed.item
---
---@field kind mdtypes.parsed.kind
---@field name string Name of `class`/`alias`/`function`.
---@field lines string[] Lines containing this parsed items(leading whitespaces are removed).
```

Gets the given class via it's name from the file.

### eval

Example,

    ```lua eval: 1 + 1
    ```

Result,

```lua eval: 1 + 1
1 + 1 = 2
```

Evaluates given `expression` and shows the returned value.

>[!IMPORTANT]
> This will evaluate **everything** after `:` as lua. So, use this as the last item.

### from

Example,

    ```lua from: ./lua/types/mdtypes.lua
    ```

Specify a `.lua` file to pull the definitions from. There can only be 1 path per code block.

>[!NOTE]
> The path is relative to the `markdown` file!

To reduce the need of writing the same path over & over again you can use `variables` in paths. See [variables](#variables) on how to set them.

Variables are written as `$` followed by any number of capital letters. So, `$VAR` is a valid variable, but `$var` is not.

Variables can also be within the path itself(e.g. `$NVIM/lua/editor/options.lua`). The variables doesn't need to be defined in the same code block and can be defined in any other code block.

Example,

    ```lua $PATH: ./lua/types/, $FILE: mdtypes.lua, from: $PATH$FILE class: mdtypes.parsed.item
    ```

Result,

```lua $PATH: ./lua/types/, $FILE: mdtypes.lua, from: $PATH$FILE, class: mdtypes.parsed.item
---@class mdtypes.parsed.item
---
---@field kind mdtypes.parsed.kind
---@field name string Name of `class`/`alias`/`function`.
---@field lines string[] Lines containing this parsed items(leading whitespaces are removed).
```

### field

Example,

    ```lua from: ./lua/mdtypes.lua, field: mdtypes._definitions
    ```

Result,

```lua from: ./lua/mdtypes.lua, function: funcdecl
---@param TSNode TSNode
---@param buffer integer
---@return table
funcdecl = function (TSNode, buffer)
	local R = { TSNode:range() };
	local flines = vim.api.nvim_buf_get_lines(buffer, R[1], R[3] + 1, false);

	local fname_node = TSNode:field("name")[1];
	local fname = fname_node and vim.treesitter.get_node_text(fname_node, buffer, {}) or nil;

	return {
		kind = "function",
		name = fname,
		funcdef = fname,

		lines = remove_leader(flines, string.match(flines[1] or "", "^%s*"))
	};
end,
```

Gets the field from it's name. Supports `foo.bar` & `foo.bar.baz[1]` syntax.

>[!IMPORTANT]
> This won't pull type definitions!

### funcref

Example,

    ```lua from: ./lua/mdtypes.lua, funcref: mdtypes._definitions
    ```

Result,

```lua from: ./lua/mdtypes.lua, funcref: mdtypes._definitions
--[[ Gets definitions from `path`. ]]
---@param path string
---@return mdtypes.parsed
```

Gets the literal definition of a function via it's name from the file.

### function

Example,

    ```lua from: ./lua/mdtypes.lua, function: mdtypes._eval
    ```

Result,

```lua from: ./lua/mdtypes.lua, function: mdtypes._eval
mdtypes._eval = function (expr)
	---|fS

	local could_eval, evaled = pcall(load, "return " .. expr);

	if could_eval and evaled then
		local could_call, value = pcall(evaled);

		if could_call then
			return expr .. " = " .. vim.inspect(value);
		end
	end

	return "";

	---|fE
end
```

Gets the function definition via it's name from the file.

### variables

Example,

    ```lua $VAR: ./lua/types/mdtypes.lua, from: $VAR, class: mdtypes.code_block
    ```

Result,

```lua $VAR: ./lua/types/mdtypes.lua, from: $VAR, class: mdtypes.code_block
---@class mdtypes.code_block Parsed code block.
---
---@field path? string File path(relative to the markdown file). May contain `$VAR` style variables.
---@field range integer[] Tree-sitter node range(`[ row_start, col_start, row_end, col_end ]`).
---@field data mdtypes.code_block.data.item[] List of data to put inside the code block.
```

Sets path variable. Variable names must only contain Uppercase letters.

They can be defined in any code blocks and can be used in any other code blocks. Only works inside [from](#from).

