local mdtypes = {};

mdtypes.get_classes = function (path)
	local could_open, result = pcall(vim.fn.readfile, vim.fn.expand("%:h") .. "/" .. path);

	if not could_open then
		result = { result };
	end

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
