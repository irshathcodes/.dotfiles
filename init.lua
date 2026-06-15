vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

vim.o.confirm = true

-- Bootstrap Lazy package manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- Leader key must be set before plugins
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Plugin configuration
-- plugin start
require("lazy").setup({
	-- Colorscheme
	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		priority = 1000,
		config = function(_, _opts)
			require("kanagawa").setup({
				keywordStyle = { italic = false },
				statementStyle = { bold = false },
				commentStyle = { italic = false },
				functionStyle = { bold = false },
			})
			vim.cmd.colorscheme("kanagawa")
		end,
	},

	-- Treesitter for better syntax highlighting
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		opts = {
			ensure_installed = {
				"lua",
				"vim",
				"vimdoc",
				"query",
				"javascript",
				"typescript",
				"tsx",
				"json",
				"html",
				"css",
				"bash",
				"rust",
				"toml",
			},
			sync_install = false,
			auto_install = true,
			highlight = {
				enable = true,
				additional_vim_regex_highlighting = false,
			},
			indent = { enable = true },
		},
		config = function(_, opts)
			require("nvim-treesitter.configs").setup(opts)
		end,
	},

	-- Auto pairs for brackets, quotes, etc.
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		opts = {},
	},

	-- Easy commenting
	{
		"numToStr/Comment.nvim",
		opts = {},
	},

	-- Surround text objects: ys / cs / ds
	{
		"kylechui/nvim-surround",
		version = "*",
		event = "VeryLazy",
		opts = {},
	},

	{
		"ThePrimeagen/harpoon",
		branch = "harpoon2",
		dependencies = { "nvim-lua/plenary.nvim" },
		config = function()
			local harpoon = require("harpoon")
			harpoon.setup()

			vim.keymap.set("n", "<leader>a", function()
				harpoon:list():add()
			end)

			vim.keymap.set("n", "<leader>f", function()
				harpoon.ui:toggle_quick_menu(harpoon:list())
			end)

			vim.keymap.set("n", "<leader>1", function()
				harpoon:list():select(1)
			end)
			vim.keymap.set("n", "<leader>2", function()
				harpoon:list():select(2)
			end)
			vim.keymap.set("n", "<leader>3", function()
				harpoon:list():select(3)
			end)
			vim.keymap.set("n", "<leader>4", function()
				harpoon:list():select(4)
			end)

			-- Toggle previous & next buffers stored within Harpoon list
			vim.keymap.set("n", "<leader>[", function()
				harpoon:list():prev()
			end)
			vim.keymap.set("n", "<leader>]", function()
				harpoon:list():next()
			end)

			local harpoon_extensions = require("harpoon.extensions")

			harpoon:extend(harpoon_extensions.builtins.highlight_current_file())
		end,
	},

	-- LSP Configuration
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"j-hui/fidget.nvim",
		},
		config = function()
			-- Setup Mason
			require("mason").setup({
				ui = {
					border = "rounded",
					icons = {
						package_installed = "✓",
						package_pending = "➜",
						package_uninstalled = "✗",
					},
				},
			})

			-- Auto-install LSP servers (mason-lspconfig v2 auto-enables installed servers)
			require("mason-lspconfig").setup({
				ensure_installed = {
					"ts_ls",
					"tailwindcss",
					"html",
					"cssls",
					"jsonls",
					"lua_ls",
					"bashls",
					"rust_analyzer",
				},
			})

			-- LSP progress notifications
			require("fidget").setup({})

			-- Helper: detect if a standalone file uses Deno-style npm: imports
			local function has_npm_imports(fname)
				local ok, lines = pcall(vim.fn.readfile, fname, "", 50)
				if not ok then
					return false
				end
				for _, line in ipairs(lines) do
					if line:match("[\"']npm:") then
						return true
					end
				end
				return false
			end

			-- Global capabilities for every server (extended by blink.cmp)
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})

			vim.lsp.config("ts_ls", {
				root_markers = { "package.json", "tsconfig.json" },
				workspace_required = true,
				settings = {
					typescript = {
						inlayHints = {
							includeInlayParameterNameHints = "literals",
							includeInlayFunctionParameterTypeHints = true,
							includeInlayFunctionLikeReturnTypeHints = true,
						},
					},
					javascript = {
						inlayHints = {
							includeInlayParameterNameHints = "literals",
							includeInlayFunctionParameterTypeHints = true,
							includeInlayFunctionLikeReturnTypeHints = true,
						},
					},
				},
			})

			vim.lsp.config("tailwindcss", {
				settings = {
					tailwindCSS = {
						classFunctions = { "cva", "cx" },
						experimental = {
							classRegex = {
								-- Match: const ANYTHING_CLS = "tailwind classes here"
								-- { "\\w*_CN\\s*=\\s*['\"`]([^'\"`]*)['\"`]" },
							},
						},
					},
				},
			})

			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = {
							library = vim.api.nvim_get_runtime_file("", true),
							checkThirdParty = false,
						},
						telemetry = { enable = false },
					},
				},
			})

			vim.lsp.config("rust_analyzer", {
				settings = {
					["rust-analyzer"] = {
						check = { command = "clippy" },
						cargo = { allFeatures = true },
					},
				},
			})

			vim.lsp.config("denols", {
				cmd = { vim.fn.expand("~/.deno/bin/deno"), "lsp" },
				workspace_required = true,
				root_dir = function(bufnr, on_dir)
					local fname = vim.api.nvim_buf_get_name(bufnr)
					local root = vim.fs.root(bufnr, { "deno.json", "deno.jsonc" })
					if root then
						on_dir(root)
					elseif has_npm_imports(fname) then
						on_dir(vim.fn.fnamemodify(fname, ":h"))
					end
				end,
				settings = { deno = { enable = true } },
			})

			-- denols isn't installed via Mason, so enable it explicitly
			vim.lsp.enable("denols")

			-- LSP keybindings
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
				callback = function(event)
					local map = function(keys, func, desc)
						vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
					end

					map("gd", vim.lsp.buf.definition, "Goto Definition")
					vim.keymap.set("n", "grr", function()
						Snacks.picker.lsp_references()
					end, { desc = "Goto References" })
					map("gI", function()
						Snacks.picker.lsp_implementations()
					end, "Goto Implementation")
					map("gt", function()
						Snacks.picker.lsp_type_definitions()
					end, "Type Definition")
					map("<leader>st", function()
						Snacks.picker.lsp_symbols()
					end, "Document Symbols")
					map("<leader>sT", function()
						Snacks.picker.lsp_workspace_symbols()
					end, "Workspace Symbols")
					map("gh", vim.lsp.buf.hover, "Hover Documentation")
					map("gD", vim.lsp.buf.declaration, "Goto Declaration")

					-- Highlight references under cursor
					local client = vim.lsp.get_client_by_id(event.data.client_id)
					if client and client.server_capabilities.documentHighlightProvider then
						local highlight_group = vim.api.nvim_create_augroup("lsp-highlight", { clear = false })
						vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
							buffer = event.buf,
							group = highlight_group,
							callback = vim.lsp.buf.document_highlight,
						})
						vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
							buffer = event.buf,
							group = highlight_group,
							callback = vim.lsp.buf.clear_references,
						})
					end
				end,
			})

			-- Clean up highlight autocmds when LSP detaches (e.g. on :LspRestart)
			vim.api.nvim_create_autocmd("LspDetach", {
				group = vim.api.nvim_create_augroup("lsp-detach", { clear = true }),
				callback = function(event)
					vim.lsp.buf.clear_references()
					pcall(vim.api.nvim_clear_autocmds, { group = "lsp-highlight", buffer = event.buf })
				end,
			})
		end,
	},

	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			delay = 2000,
		},
	},

	-- Autocompletion
	{
		"saghen/blink.cmp",

		-- use a release tag to download pre-built binaries
		version = "1.*",

		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			-- 'default' (recommended) for mappings similar to built-in completions (C-y to accept)
			-- 'super-tab' for mappings similar to vscode (tab to accept)
			-- 'enter' for enter to accept
			-- 'none' for no mappings
			--
			-- All presets have the following mappings:
			-- C-space: Open menu or open docs if already open
			-- C-n/C-p or Up/Down: Select next/previous item
			-- C-e: Hide menu
			-- C-k: Toggle signature help (if signature.enabled = true)
			--
			-- See :h blink-cmp-config-keymap for defining your own keymap
			keymap = { preset = "enter" },

			appearance = {
				-- 'mono' (default) for 'Nerd Font Mono' or 'normal' for 'Nerd Font'
				-- Adjusts spacing to ensure icons are aligned
				nerd_font_variant = "mono",
			},

			-- (Default) Only show the documentation popup when manually triggered
			completion = {
				documentation = { auto_show = false },
				accept = {
					auto_brackets = {
						enabled = false,
					},
				},
			},

			signature = { enabled = true },

			-- Completion sources. Keep LSP/path, but disable the buffer source so
			-- random words from the current file are not suggested.
			sources = {
				default = { "lsp", "path" },
			},

			-- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
			-- You may use a lua implementation instead by using `implementation = "lua"` or fallback to the lua implementation,
			-- when the Rust fuzzy matcher is not available, by using `implementation = "prefer_rust"`
			--
			-- See the fuzzy documentation for more information
			fuzzy = { implementation = "prefer_rust_with_warning" },
		},
		opts_extend = { "sources.default" },
	},

	-- Formatting
	{
		"stevearc/conform.nvim",
		event = "BufWritePre",
		cmd = "ConformInfo",
		opts = {
			formatters_by_ft = {
				javascript = { "prettier" },
				typescript = { "prettier" },
				javascriptreact = { "prettier" },
				typescriptreact = { "prettier" },
				css = { "prettier" },
				html = { "prettier" },
				json = { "prettier" },
				yaml = { "prettier" },
				markdown = { "prettier" },
				lua = { "stylua" },
				rust = { "rustfmt" },
			},
			format_after_save = function(bufnr)
				if vim.b[bufnr].disable_autoformat or vim.g.disable_autoformat then
					return
				end
				local formatters = require("conform").list_formatters(bufnr)
				if #formatters == 0 then
					return
				end
				return { lsp_format = "fallback" }
			end,
		},
	},

	-- Indentation guides
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		opts = {
			indent = { char = "│" },
			scope = {
				enabled = true,
				show_start = false,
				show_end = false,
			},
		},
	},

	-- Git signs
	{
		"lewis6991/gitsigns.nvim",
		opts = {
			signs = {
				add = { text = "+" },
				change = { text = "~" },
				delete = { text = "_" },
				topdelete = { text = "‾" },
				changedelete = { text = "~" },
			},
			on_attach = function(bufnr)
				local gitsigns = require("gitsigns")

				local function map(mode, l, r, opts)
					opts = opts or {}
					opts.buffer = bufnr
					vim.keymap.set(mode, l, r, opts)
				end

				-- Navigation
				map("n", "]c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "]c", bang = true })
					else
						gitsigns.nav_hunk("next")
					end
				end, { desc = "go to next hunk" })

				map("n", "[c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gitsigns.nav_hunk("prev")
					end
				end, { desc = "go to prev hunk" })

				-- Actions
				map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "stage hunk" })
				map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "reset hunk" })

				map("v", "<leader>hs", function()
					gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end)

				map("v", "<leader>hr", function()
					gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end)

				map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "stage buffer" })
				map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "reset buffer" })
				map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "preview hunk" })
				map("n", "<leader>hi", gitsigns.preview_hunk_inline, { desc = "preview hunk inline" })

				map("n", "<leader>hb", function()
					gitsigns.blame_line({ full = true })
				end, { desc = "open blame line full" })

				map("n", "<leader>hQ", function()
					gitsigns.setqflist("all")
				end)
				map("n", "<leader>hq", gitsigns.setqflist)

				-- Toggles
				map("n", "<leader>tb", gitsigns.toggle_current_line_blame, { desc = "toggle current line blame" })
			end,
		},
	},
	{
		"nvim-lualine/lualine.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		config = function(_, _)
			require("lualine").setup({
				sections = {
					lualine_a = {},
					lualine_b = { "branch", "diff" },
					lualine_c = { { "filename", path = 1, symbols = { modified = " ●" } } },
					lualine_x = { "diagnostics" },
				},
			})
		end,
	},
	{
		"stevearc/oil.nvim",
		---@module 'oil'
		---@type oil.SetupOpts
		opts = {
			default_file_explorer = false,
			view_options = {
				show_hidden = true,
			},
			watch_for_changes = true,
			keymaps = {
				["<C-r>"] = "actions.refresh",
			},
		},
		dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if you prefer nvim-web-devicons
		lazy = false,
	},
	{
		"folke/snacks.nvim",
		---@type snacks.Config
		opts = {
			picker = {
				sources = {
					explorer = {
						layout = {
							auto_hide = { "input" },
							layout = {
								position = "right",
								width = 0.30,
							},
						},
						hidden = true,
						ignored = true,
						auto_close = false,
						win = {
							list = {
								keys = {
									["e"] = "toggle_maximize",
								},
							},
						},
					},
					smart = {
						layout = { preset = "dropdown", preview = false },
					},
				},
			},
		},
		config = function(_, opts)
			require("snacks").setup(opts)
			vim.api.nvim_set_hl(0, "SnacksPickerTree", { fg = "#54546d", bg = "NONE" })
		end,
	},
	{
		"rmagatti/auto-session",
		lazy = false,

		---enables autocomplete for opts
		---@module "auto-session"
		---@type AutoSession.Config
		opts = {
			suppressed_dirs = { "~/", "~/Projects", "~/Downloads", "/" },
		},
	},
	{
		"kevinhwang91/nvim-ufo",
		event = "BufEnter",
		dependencies = {
			"kevinhwang91/promise-async",
		},
		config = function()
			--- @diagnostic disable: unused-local
			local ufo = require("ufo")

			ufo.setup({
				provider_selector = function(_bufnr, _filetype, _buftype)
					return { "treesitter", "indent" }
				end,
			})
		end,
	},
})
-- plugins end

-- Editor settings
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.autoindent = true
vim.opt.wrap = true
vim.opt.scrolloff = 8
-- vim.opt.sidescrolloff = 8
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.mouse = "a"
-- vim.opt.clipboard = "unnamedplus"
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.updatetime = 250

vim.opt.undofile = true
vim.opt.breakindent = true

-- Fold settings
vim.o.foldcolumn = "0"
vim.opt.foldmethod = "manual"
vim.opt.foldlevel = 99 -- Allow folds to be created
vim.opt.foldlevelstart = 99 -- Open all folds when opening a file
vim.opt.foldenable = true

vim.diagnostic.config({ update_in_insert = false })

-- Close floating windows (like hover docs) and clear search highlight on Escape
vim.keymap.set("n", "<Esc>", function()
	-- Close floating windows
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local config = vim.api.nvim_win_get_config(win)
		if config.relative ~= "" then
			-- Skip snacks picker windows
			local buf = vim.api.nvim_win_get_buf(win)
			local ft = vim.bo[buf].filetype
			if not ft:match("^snacks_picker") then
				vim.api.nvim_win_close(win, false)
			end
		end
	end
	-- Clear search highlight
	vim.cmd("nohlsearch")
end, { desc = "Close popups and clear search" })

-- Window navigation
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

-- Move lines in visual mode
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Keep cursor centered
vim.keymap.set("n", "<C-d>", "<C-d>zz")
vim.keymap.set("n", "<C-u>", "<C-u>zz")
vim.keymap.set("n", "n", "nzzzv")
vim.keymap.set("n", "N", "Nzzzv")

-- Paragraph motions without jumplist
vim.keymap.set({ "n", "v" }, "{", "<cmd>keepjumps normal! {<CR>")
vim.keymap.set({ "n", "v" }, "}", "<cmd>keepjumps normal! }<CR>")

-- Entire-buffer text object: die, yie, vie, cie, etc.
vim.keymap.set({ "x", "o" }, "ie", ":<C-u>normal! ggVG<CR>", { silent = true, desc = "entire buffer" })
vim.keymap.set({ "x", "o" }, "ae", ":<C-u>normal! ggVG<CR>", { silent = true, desc = "entire buffer" })

vim.keymap.set("n", "<leader>e", function()
	local snacks = require("snacks.explorer")
	snacks.open()
end, { desc = "Toggle file explorer" })

vim.keymap.set("n", "-", "<cmd>Oil .<CR>", { desc = "Open Oil.nvim" })

-- Picker keymaps (snacks.nvim)
vim.keymap.set("n", "<leader>sf", function()
	Snacks.picker.smart()
end, { desc = "Find files (smart)" })
vim.keymap.set("n", "<leader>sg", function()
	Snacks.picker.grep()
end, { desc = "Live grep" })
vim.keymap.set({ "n", "v" }, "<leader>su", function()
	Snacks.picker.grep_word()
end, { desc = "Grep word under cursor" })
vim.keymap.set("n", "<leader>sb", function()
	Snacks.picker.buffers()
end, { desc = "Find buffers" })
vim.keymap.set("n", "<leader>sh", function()
	Snacks.picker.help()
end, { desc = "Help tags" })
vim.keymap.set("n", "<leader>so", function()
	Snacks.picker.recent()
end, { desc = "Recent files" })
vim.keymap.set("n", "<leader>sk", function()
	Snacks.picker.keymaps()
end, { desc = "Search keymaps" })
vim.keymap.set("n", "<leader>sr", function()
	Snacks.picker.resume()
end, { desc = "Resume last picker" })
vim.keymap.set("n", "<leader>sd", function()
	Snacks.picker.diagnostics()
end, { desc = "Workspace diagnostics" })

-- Diagnostic keymaps
vim.keymap.set("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })
vim.keymap.set("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })
vim.keymap.set("n", "ge", vim.diagnostic.open_float, { desc = "Show diagnostic under cursor" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostic quickfix list" })

-- console.log snippet in JS/TS via <C-l>
vim.api.nvim_create_autocmd("FileType", {
	pattern = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
	group = vim.api.nvim_create_augroup("js-snippets", { clear = true }),
	callback = function(args)
		vim.keymap.set("i", "<C-l>", function()
			vim.snippet.expand('console.log("$1");$0')
		end, { buffer = args.buf, desc = "console.log" })
	end,
})

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.hl.on_yank()
	end,
})

-- Command palette
local command_palette
do
	local commands = {
		{
			name = "Format file",
			action = function()
				require("conform").format({ lsp_format = "fallback", async = true })
			end,
		},
		{
			name = "Save without format",
			action = function()
				vim.b.disable_autoformat = true
				vim.cmd("write")
				vim.b.disable_autoformat = false
			end,
		},
		{
			name = "Toggle format-on-save (global)",
			action = function()
				vim.g.disable_autoformat = not vim.g.disable_autoformat
				vim.notify("format-on-save " .. (vim.g.disable_autoformat and "disabled" or "enabled"))
			end,
		},
		{
			name = "Copy file path (absolute)",
			action = function()
				local path = vim.fn.expand("%:p")
				vim.fn.setreg("+", path)
				vim.notify("Copied: " .. path)
			end,
		},
		{
			name = "Copy file path (relative)",
			action = function()
				local path = vim.fn.expand("%:.")
				vim.fn.setreg("+", path)
				vim.notify("Copied: " .. path)
			end,
		},
		{
			name = "Copy file name",
			action = function()
				local path = vim.fn.expand("%:t")
				vim.fn.setreg("+", path)
				vim.notify("Copied: " .. path)
			end,
		},
		{
			name = "Yank buffer to clipboard",
			action = function()
				vim.cmd("%y+")
				vim.notify("Yanked buffer to clipboard")
			end,
		},
		{
			name = "Restart TS server",
			action = function()
				vim.cmd("LspRestart ts_ls")
			end,
		},
		{
			name = "Restart all LSP servers",
			action = function()
				vim.cmd("LspRestart")
			end,
		},
		{
			name = "Split vertical",
			action = function()
				vim.cmd("vsplit")
			end,
		},
		{
			name = "Split horizontal",
			action = function()
				vim.cmd("split")
			end,
		},
		{
			name = "Close split",
			action = function()
				vim.cmd("close")
			end,
		},
		{
			name = "Close other splits",
			action = function()
				vim.cmd("only")
			end,
		},
		{
			name = "Close all other buffers",
			action = function()
				local current = vim.api.nvim_get_current_buf()
				local closed = 0
				for _, buf in ipairs(vim.api.nvim_list_bufs()) do
					if buf ~= current and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buflisted then
						if pcall(vim.api.nvim_buf_delete, buf, {}) then
							closed = closed + 1
						end
					end
				end
				vim.notify("Closed " .. closed .. " buffer(s)")
			end,
		},
		{
			name = "New scratch buffer",
			action = function()
				vim.cmd("enew")
				vim.bo.buftype = "nofile"
				vim.bo.bufhidden = "wipe"
				vim.bo.swapfile = false
			end,
		},
		{
			name = "Toggle inlay hints",
			action = function()
				vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
			end,
		},
		{
			name = "Toggle diagnostics",
			action = function()
				vim.diagnostic.enable(not vim.diagnostic.is_enabled())
			end,
		},
		{
			name = "Toggle word wrap",
			action = function()
				vim.wo.wrap = not vim.wo.wrap
			end,
		},
		{
			name = "Toggle spell check",
			action = function()
				vim.wo.spell = not vim.wo.spell
			end,
		},
		{
			name = "Toggle relative line numbers",
			action = function()
				vim.wo.relativenumber = not vim.wo.relativenumber
			end,
		},
		{
			name = "Open init.lua",
			action = function()
				vim.cmd("edit " .. vim.fn.stdpath("config") .. "/init.lua")
			end,
		},
		{
			name = "Reload config",
			action = function()
				vim.cmd("source $MYVIMRC")
				vim.notify("Reloaded init.lua")
			end,
		},
		{
			name = "cd to git root",
			action = function()
				local root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
				if vim.v.shell_error ~= 0 or not root or root == "" then
					vim.notify("Not in a git repo", vim.log.levels.WARN)
					return
				end
				vim.cmd("cd " .. vim.fn.fnameescape(root))
				vim.notify("cd " .. root)
			end,
		},
		{
			name = "Reveal current file in Oil",
			action = function()
				require("oil").open()
			end,
		},
		{
			name = "Reveal current file in snacks explorer",
			action = function()
				require("snacks").picker.explorer({ cwd = vim.fn.expand("%:p:h") })
			end,
		},
	}

	command_palette = function()
		local items = {}
		for _, cmd in ipairs(commands) do
			table.insert(items, { text = cmd.name, action = cmd.action })
		end

		Snacks.picker.pick({
			source = "command_palette",
			title = "Command Palette",
			items = items,
			layout = { preset = "select" },
			format = "text",
			confirm = function(picker, item)
				picker:close()
				if item and item.action then
					item.action()
				end
			end,
		})
	end
end

vim.keymap.set({ "n", "v" }, "<leader>k", command_palette, { desc = "Command palette" })

vim.api.nvim_create_user_command("TermHl", function()
	local b = vim.api.nvim_create_buf(false, true)
	local chan = vim.api.nvim_open_term(b, {})
	vim.api.nvim_chan_send(chan, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
	vim.api.nvim_win_set_buf(0, b)
end, { desc = "Highlights ANSI termcodes in curbuf" })
