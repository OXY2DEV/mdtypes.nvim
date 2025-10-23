local md = {};

md.get_classes = function (path)
	local could_open, result = pcall(vim.fn.readfile, path);

	if not could_open then
		return;
	end

	local classes = {};
	local buffer = {};

	local in_class = false;

	for _, line in ipairs(result) do
		if string.match(line, "^%s*$") then
			if in_class then
				classes[#classes].lines = buffer;
			end

			buffer = {};
			in_class = false
		elseif string.match(line, "^[%s%-]+@class") then
			if in_class then
				classes[#classes].lines = buffer;
			end

			table.insert(classes, { lines = {} });
			buffer = { line };
			in_class = true;
		else
			table.insert(buffer, line);
		end
	end

	vim.print(classes)
end

md.parse = function (buffer)
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
			return;
		end
	end);

	return output;

	---|fE
end

return md;
