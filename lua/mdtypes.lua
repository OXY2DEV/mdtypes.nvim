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

--[[ Gets function declarations & definitions. ]]
---@param path string
---@return mdtypes.parsed
mdtypes._function = function (path)
	---|fS

	local could_open, lines = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		return {};
	end

	local buf = vim.api.nvim_create_buf(false, true);
	vim.bo[buf].ft = "lua";

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines);

	local functions = {};
	local query = vim.treesitter.query.parse("lua", [[
		(function_declaration
			name: (_)) @funcdecl

		(function_definition) @funcdef
	]]);

	local root_parser = vim.treesitter.get_parser(buf);

	if not root_parser then
		return {};
	end

	local function remove_leader (entries, row_start)
		local _lines = {};

		for _, line in ipairs(entries) do
			table.insert(_lines, string.sub(line, row_start));
		end

		return _lines;
	end

	root_parser:parse(true);
	root_parser:for_each_tree(function (TSTree, LanguageTree)
		if LanguageTree:lang() == "lua" then
			for capture_id, capture_node, _, _ in query:iter_captures(TSTree:root(), buf) do
				local name = query.captures[capture_id];

				if name == "funcdecl" then
					local R = { capture_node:range() };
					local flines = vim.api.nvim_buf_get_lines(buf, R[1], R[3] + 1, false);

					local fname_node = capture_node:field("name")[1];

					table.insert(functions, {
						kind = "function",
						name = fname_node and vim.treesitter.get_node_text(fname_node, buf, {}) or nil,

						lines = remove_leader(flines, #string.match(flines[1] or "", "^%s*"))
					});
				elseif name == "funcdef" then
					local R = { capture_node:range() };
					local flines = vim.api.nvim_buf_get_lines(buf, R[1], R[3] + 1, false);

					local fname = string.match(flines[1] or "", "(%S+)%s*=%s*function");

					table.insert(functions, {
						kind = "function",
						name = fname,

						lines = remove_leader(flines, #string.match(flines[1] or "", "^%s*"))
					});
				end
			end
		end
	end);

	pcall(vim.api.nvim_buf_delete, buf, true);
	return functions;

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
					functions = mdtypes._function(block.path),
				};
			end

			local this = mdtypes.__cache[block.path];
			local is_fn = entry.kind == "function";

			for _, item in ipairs(not is_fn and this.definitions or this.functions) do
				if item.kind == entry.kind and item.name == entry.value then
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
	vim.api.nvim_create_user_command("Types", function ()
		mdtypes.generate();
	end, {
		nargs = 0,
		desc = "Generate type definitions & evaluation results for code blocks in markdown."
	});
end

return mdtypes;
