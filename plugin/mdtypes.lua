vim.api.nvim_create_user_command("Types", function ()
	require("mdtypes").generate();
end, {
	nargs = 0,
	desc = "Generate type definitions & evaluation results for code blocks in markdown."
});

