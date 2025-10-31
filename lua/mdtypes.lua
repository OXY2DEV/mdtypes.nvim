local mdtypes = {};

--[[ Gets annotations from `path`. ]]
---@param path string
---@return table
mdtypes._annotations = function (path)
	---|fS

	local could_open, lines = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		return {};
	end

	local annotations = {};
	local buffer = {};

	local is_within_chunk = false;

	local function flush (line)
		if is_within_chunk and #annotations > 0 then
			table.insert(buffer, line);
			vim.list_extend(annotations[#annotations].lines or {}, buffer);

			is_within_chunk = false;
		end

		buffer = {};
	end

	for _, line in ipairs(lines) do
		line = string.gsub(line, "^%s+", "");

		if string.match(line, "^%s*$") then
			flush();
		elseif not string.match(line, "^%s*%-%-+") then
			if #buffer > 0 and ( string.match(line, "(%w+)%s*=%s*function") or string.match(line, "function%s+(%w+)") ) then
				local name = string.match(line, "(%w+)%s*=%s*function") or string.match(line, "function%s+(%w+)");

				table.insert(annotations, {
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
				flush();
				table.insert(annotations, {
					kind = kind,
					name = name,
					lines = { line }
				});
				is_within_chunk = true;
			else
				table.insert(buffer, line);
			end
		else
			table.insert(buffer, line);
		end
	end

	flush();
	return annotations;

	---|fE
end

mdtypes._function = function (path)
	---|fS

	local could_open, lines = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		return {};
	end

	local buf = vim.api.nvim_create_buf(false, true);
	vim.bo[buf].ft = "lua";

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines);

	local annotations = {};
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
				vim.print(name);

					table.insert(annotations, {
						kind = "functdecl",
						name = fname_node and vim.treesitter.get_node_text(fname_node, buf, {}) or nil,

						lines = remove_leader(flines, #string.match(flines[1] or "", "^%s*"))
					});
				elseif name == "funcdef" then
					local R = { capture_node:range() };
					local flines = vim.api.nvim_buf_get_lines(buf, R[1], R[3] + 1, false);

					local fname = string.match(flines[1] or "", "(%S+)%s*=%s*function");

					table.insert(annotations, {
						kind = "functdecl",
						name = fname,

						lines = remove_leader(flines, #string.match(flines[1] or "", "^%s*"))
					});
				end
			end
		end
	end)

	return annotations;

	---|fE
end

mdtypes._eval = function (expr)
	return vim.api.nvim_exec2("=" .. expr, { output = true }).output;
end

mdtypes.get_classes = function (path)
	local could_open, result = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		result = { result };
	end

-- vim.print(
-- 	pcall(mdtypes._eval, 'vim')
-- );

	local classes = {};
	local tmp = {};

	local output = {};

	local in_class = false;

	for _, line in ipairs(result) do
		if not string.match(line, "^%s*%-%-%-+") then
			if in_class and #classes > 0 then
				classes[#classes].lines = tmp;

				local last_name = classes[#classes].name;
				output[last_name] = classes[#classes];
			end

			tmp = {};
			in_class = false
		elseif string.match(line, "^.*%-%-%-+@alias%s+(%S+)") then
			if in_class then
				classes[#classes].lines = tmp;

				local last_name = classes[#classes].name;
				output[last_name] = classes[#classes];
			end

			table.insert(tmp, line);
			table.insert(classes, {
				name = string.match(line, "^.*%-%-%-+@alias%s+(%S+)"),
				lines = tmp
			});
			in_class = true;
		elseif string.match(line, "^.*%-%-%-+@type%s+(%S+)") then
			if in_class then
				classes[#classes].lines = tmp;

				local last_name = classes[#classes].name;
				output[last_name] = classes[#classes];
			end

			table.insert(tmp, line);
			table.insert(classes, {
				name = string.match(line, "^.*%-%-%-+@type%s+(%S+)"),
				lines = tmp
			});
			in_class = true;
		elseif string.match(line, "^.*%-%-%-+@class%s+(%S+)") then
			if in_class then
				classes[#classes].lines = tmp;

				local last_name = classes[#classes].name;
				output[last_name] = classes[#classes];
			end

			table.insert(tmp, line);
			table.insert(classes, {
				name = string.match(line, "^.*%-%-%-+@class%s+(%S+)"),
				lines = tmp
			});
			in_class = true;
		else
			table.insert(tmp, line);
		end
	end

	if in_class and #tmp > 0 then
		classes[#classes].lines = tmp;

		local last_name = classes[#classes].name;
		output[last_name] = classes[#classes];
	end

	return classes, output;
end

mdtypes.parse = function (buffer)
	---|fS

	local root_parser = vim.treesitter.get_parser(buffer);

	if not root_parser then
		return;
	end

	root_parser:parse(true);
	local output = {};

	root_parser:for_each_tree(function (TSTree, language_tree)
		local lang = language_tree:lang();

		if lang == "markdown" then
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
					local from = string.match(text, "from: (%S+)");
					local class = string.match(text, "class: (%S+)");

					if from and class then
						table.insert(output, 1, {
							range = { capture_node:range() },

							from = from,
							class = class
						});
					end
				end
			end
		end
	end);

	return output;

	---|fE
end

mdtypes.generate = function (buffer)
	buffer = buffer or vim.api.nvim_get_current_buf();
	local matches = mdtypes.parse(buffer);

	vim.api.nvim_buf_call(buffer, function ()
		local map = {};

		for _, match in ipairs(matches or {}) do
			if not map[match] then
				_, map.match = mdtypes.get_classes(match.from);
			end

			if map.match[match.class] then
				local R = match.range;
				vim.api.nvim_buf_set_lines(buffer, R[1] + 1, R[3] - 1, false, map.match[match.class].lines);
			end
		end
	end)

	-- vim.print(matches);
end

mdtypes.setup = function ()
	vim.api.nvim_create_user_command("Types", function ()
		mdtypes.generate();
	end, {
		nargs = 0,
		desc = "Fill types"
	})
end

return mdtypes;
