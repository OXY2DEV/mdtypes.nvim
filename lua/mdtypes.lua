local mdtypes = {};

mdtypes.generate = function (buffer)
	buffer = buffer or vim.api.nvim_get_current_buf();
	local matches = require("mdtypes.markdown").parse(buffer);

	for _, match in ipairs(matches) do
		require("mdtypes.markdown").get_classes(match.from)
	end

	vim.print(matches);
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
