---@param entries string[]
---@param whitespaces string
---@return string[]
local function remove_leader (entries, whitespaces)
	local _lines = {};
	local pattern = string.rep("%s", whitespaces:len() or 0);

	for _, line in ipairs(entries) do
		local fixed = string.gsub(line, "^" .. pattern, "");
		table.insert(_lines, fixed);
	end

	return _lines;
end

local mdtypes = {};

--[[ Gets definitions from `path`. ]]
---@param path string
---@return mdtypes.parsed
mdtypes._definitions = function (path)
	---|fS

	local could_open, lines = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		return {};
	end

	local definitions = {};
	local buffer = {};

	local is_within_chunk = false;

	local function flush (line)
		if is_within_chunk and #definitions > 0 then
			table.insert(buffer, line);
			vim.list_extend(definitions[#definitions].lines or {}, buffer);

			is_within_chunk = false;
		end

		buffer = {};
	end

	for _, line in ipairs(lines) do
		line = string.gsub(line, "^%s+", "");

		if string.match(line, "^%s*$") then
			flush();
		elseif not string.match(line, "^%s*%-%-+") then
			if #buffer > 0 and ( string.match(line, "(%S+)%s*=%s*function") or string.match(line, "function%s+(%w+)") ) then
				local name = string.match(line, "(%S+)%s*=%s*function") or string.match(line, "function%s+(%w+)");

				table.insert(definitions, {
					kind = "funcref",
					name = name,
					lines = buffer
				});

				buffer = {};
			else
				flush();
			end
		elseif string.match(line, "^%s*%-%-%-+@%w+") then
			local valid = {
				"class",
				"alias",
			};
			local kind, name = string.match(line, "^%s*%-%-%-+@(%w+)%s*(%S+)");

			if vim.list_contains(valid, kind) then
				-- Annotation.

				if string.match(buffer[#buffer] or "", "^%s*%-%-%-+@%w+") then
					flush();
					table.insert(definitions, {
						kind = kind,
						name = name,
						lines = { line }
					});
				else
					local _lines = vim.deepcopy(buffer);
					table.insert(_lines, line);
					buffer = {};

					table.insert(definitions, {
						kind = kind,
						name = name,
						lines = _lines
					});
				end

				is_within_chunk = true;
			else
				table.insert(buffer, line);
			end
		else
			table.insert(buffer, line);
		end
	end

	flush();
	return definitions;

	---|fE
end

---@type table<string, function>
mdtypes.lua_processors = {
	---@param TSNode TSNode
	---@param buffer integer
	---@return table?
	funcdecl = function (TSNode, buffer)
		local R = { TSNode:range() };
		local flines = vim.api.nvim_buf_get_lines(buffer, R[1], R[3] + 1, false);

		local fname_node = TSNode:field("name")[1];
		local fname = fname_node and vim.treesitter.get_node_text(fname_node, buffer, {}) or nil;

		if not fname then
			return;
		end

		return {
			kind = "function",
			name = fname,
			funcref = fname,

			lines = remove_leader(flines, string.match(flines[1] or "", "^%s*"))
		};
	end,
	funcdef = function (TSNode, buffer)
		local R = { TSNode:range() };
		local flines = vim.api.nvim_buf_get_lines(buffer, R[1], R[3] + 1, false);

		local fname = string.match(flines[1] or "", "(%S+)%s*=%s*function");

		if not fname then
			return;
		end

		if not TSNode:parent() or TSNode:parent():type() ~= "field" then
			return {
				kind = "function",
				name = fname,
				funcref = fname,

				lines = remove_leader(flines, string.match(flines[1] or "", "^%s*"))
			};
		end
	end,
	variable = function (TSNode, buffer)
		local R = { TSNode:range() };
		local vlines = vim.api.nvim_buf_get_lines(buffer, R[1], R[3] + 1, false);

		local vname = string.match(vlines[1] or "", "(%S+)%s*=");

		if string.match(vname, "%.") then
			-- NOTE: `foo.bar` assignments are fields not variables.
			return {
				kind = "field",
				name = vname,
				funcref = vname,

				lines = remove_leader(vlines, string.match(vlines[1] or "", "^%s*"))
			};
		end

		return {
			kind = "var",
			name = vname,

			lines = remove_leader(vlines, string.match(vlines[1] or "", "^%s*"))
		};
	end,
	field = function (TSNode, buffer)
		---@param node TSNode
		---@return string
		local function field_name (node)
			local txt = vim.treesitter.get_node_text(node, buffer, {});

			if string.match(txt, "^[^{]") then
				local matched = string.match(txt, "^(.-)%s*=") or txt;

				matched = string.gsub(matched, '^%["', ""):gsub('"%]$', "");
				matched = string.gsub(matched, "^%['", ""):gsub("'%]$", "");

				if string.match(matched, "^%[") then
					return matched;
				else
					return "." .. matched;
				end
			else
				local N = 1;
				local prev = node:prev_named_sibling();

				while prev do
					if prev:type() == "field" then
						N = N + 1;
					end

					prev = prev:prev_named_sibling();
				end

				return string.format("[%d]", N);
			end
		end

		local R = { TSNode:range() };
		local flines = vim.api.nvim_buf_get_lines(buffer, R[1], R[3] + 1, false);

		local fname = field_name(TSNode);
		local funcref = string.gsub(fname or "", "^%.", "");

		local parent = TSNode:parent();

		while parent do
			if parent:type() == "field" then
				fname = field_name(parent) .. fname;
			elseif parent:type() == "assignment_statement" then
				fname = field_name(parent) .. fname;
				break;
			end

			parent = parent:parent();
		end

		if not fname or fname == "" then
			return;
		end

		fname = string.gsub(fname, "^%.", "");

		return {
			kind = "field",
			name = fname,
			funcref = funcref,

			lines = remove_leader(flines, string.match(flines[1] or "", "^%s*"))
		};
	end
};

--[[ Gets lua variable, functions etc. from `path`. ]]
---@param path string
---@return mdtypes.parsed
mdtypes._lua = function (path)
	---|fS

	local could_open, lines = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		return {};
	end

	local buf = vim.api.nvim_create_buf(false, true);
	vim.bo[buf].ft = "lua";

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines);

	local lua = {};
	local query = vim.treesitter.query.parse("lua", [[
		(function_declaration
			name: (_)) @funcdecl

		(function_definition) @funcdef

		(assignment_statement) @variable
		(field) @field
	]]);

	local root_parser = vim.treesitter.get_parser(buf);

	if not root_parser then
		return {};
	end

	root_parser:parse(true);
	root_parser:for_each_tree(function (TSTree, LanguageTree)
		if LanguageTree:lang() == "lua" then
			for capture_id, capture_node, _, _ in query:iter_captures(TSTree:root(), buf) do
				local name = query.captures[capture_id];
				local can_cal, val = pcall(mdtypes.lua_processors[name], capture_node, buf);

				if can_cal then
					table.insert(lua, val);
				end
			end
		end
	end);

	pcall(vim.api.nvim_buf_delete, buf, true);
	return lua;

	---|fE
end

---[[ Evaluates given expression. ]]
---@param expr string
---@return string
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

--- Parse code blocks.
---@param buffer integer
---@return mdtypes.code_block[]
mdtypes.parse = function (buffer)
	---|fS

	local root_parser = vim.treesitter.get_parser(buffer);

	if not root_parser then
		return {};
	end

	root_parser:parse(true);
	local output = {};
	local vars = {};

	---@param TSTree TSTree
	local function get_code_blocks (TSTree)
		local query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @block");

		for _, capture_node, _, _ in query:iter_captures(TSTree:root(), buffer) do
			local info_string;

			for child in capture_node:iter_children() do
				if child:type() == "info_string" then
					info_string = child;
					break;
				end
			end

			if info_string then
				local text = vim.treesitter.get_node_text(info_string, buffer, {});

				local properties = {
					range = { capture_node:range() },
					data = {},
				};

				if string.match(text, "eval: %S.*$") then
					table.insert(properties.data, {
						kind = "eval",
						value = string.match(text, "eval: (.+)$")
					});

					text = string.gsub(text, "eval: .+$", "");
				end

				local parts = vim.fn.split(text, ",", false);

				for _, part in ipairs(parts) do
					for key, value in string.gmatch(part, "([^%s:]+): ([^%s,]+)") do
						if key == "from" then
							properties.path = string.gsub(value, "%$[a-zA-Z]+", function (k)
								if vars[k] then
									return vars[k];
								end

								return "";
							end);
						elseif string.match(key, "^%$") then
							vars[key] = value;
						else
							table.insert(properties.data, {
								kind = key,
								value = value
							});
						end
					end
				end

				if vim.tbl_isempty(properties.data) == false then
					table.insert(output, 1, properties);
				end
			end
		end
	end

	root_parser:for_each_tree(function (TSTree, language_tree)
		local lang = language_tree:lang();

		if lang == "markdown" then
			get_code_blocks(TSTree);
		end
	end);

	return output;

	---|fE
end

---@type table<string, mdtyles.cache.buf> Cached parsed data.
mdtypes.__cache = {};

---@param block mdtypes.code_block
---@return string[]
mdtypes.fill = function (block)
	---|fS

	local lines = {};

	local function get_funcref (this, funcname)
		if not funcname then
			return;
		elseif not this.definitions then
			return;
		end

		for _, item in ipairs(this.definitions) do
			if item.kind == "funcref" and item.name == funcname then
				lines = vim.list_extend(lines, item.lines);
				break;
			end
		end
	end

	for e, entry in ipairs(block.data) do
		if entry.kind == "eval" then
			vim.list_extend(
				lines,
				vim.fn.split(
					mdtypes._eval(entry.value),
					"\n"
				)
			);
		elseif block.path then
			if not mdtypes.__cache[block.path] then
				mdtypes.__cache[block.path] = {
					definitions = mdtypes._definitions(block.path),
					lua = mdtypes._lua(block.path),
				};
			end

			local this = mdtypes.__cache[block.path];
			local is_lua = entry.kind == "function" or entry.kind == "var" or entry.kind == "field";

			for _, item in ipairs(not is_lua and this.definitions or this.lua) do
				if item.kind == entry.kind and item.name == entry.value then
					get_funcref(this, item.funcref);
					lines = vim.list_extend(lines, item.lines);

					if e ~= #block.data then
						table.insert(lines, "");
					end

					break;
				end
			end
		end
	end

	return lines;

	---|fE
end

--- Generates text inside code blocks.
---@param buffer? integer
mdtypes.generate = function (buffer)
	---|fS

	mdtypes.__cache = {};

	buffer = buffer or vim.api.nvim_get_current_buf();
	local blocks = mdtypes.parse(buffer);

	vim.api.nvim_buf_call(buffer, function ()
		for _, block in ipairs(blocks) do
			local _lines = mdtypes.fill(block);

			if #_lines > 0 then
				local R = block.range;
				local start = vim.api.nvim_buf_get_lines(buffer, R[1], R[1], false)[1];
				local delimiter = string.match(start or "", "^[^`]+");

				if delimiter then
					for l, line in ipairs(_lines) do
						_lines[l] = delimiter .. line;
					end
				end

				vim.api.nvim_buf_set_lines(buffer, R[1] + 1, R[3] - 1, false, _lines);
			end
		end
	end);

	---|fE
end

mdtypes.setup = function ()
	-- No setup needed.
end

return mdtypes;
