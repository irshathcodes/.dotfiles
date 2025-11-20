vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Bootstrap Lazy package manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
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
require("lazy").setup({
	-- Colorscheme
	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		priority = 1000,
		opts = {},
		config = function(_, opts)
			require("kanagawa").setup(opts)
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

	-- Fuzzy finder
	{
		"nvim-telescope/telescope.nvim",
		tag = "0.1.8",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {
			defaults = {
				mappings = {
					i = {
						["<C-h>"] = "which_key",
					},
				},
			},
		},
	},

	-- LSP Configuration
	{
		"neovim/nvim-lspconfig",
		dependencies = {
			"williamboman/mason.nvim",
			"williamboman/mason-lspconfig.nvim",
			"j-hui/fidget.nvim",
			"hrsh7th/cmp-nvim-lsp",
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

			-- Auto-install LSP servers
			require("mason-lspconfig").setup({
				ensure_installed = {
					"ts_ls",
					"tailwindcss",
					"html",
					"cssls",
					"jsonls",
					"lua_ls",
				},
				automatic_installation = true,
			})

			-- LSP progress notifications
			require("fidget").setup({})

			-- Capabilities for completion
			local capabilities = vim.lsp.protocol.make_client_capabilities()
			capabilities = vim.tbl_deep_extend("force", capabilities, require("cmp_nvim_lsp").default_capabilities())

			-- LSP server configurations
			local servers = {
				ts_ls = {
					settings = {
						typescript = {
							inlayHints = {
								includeInlayParameterNameHints = "all",
								includeInlayFunctionParameterTypeHints = true,
								includeInlayVariableTypeHints = true,
								includeInlayPropertyDeclarationTypeHints = true,
								includeInlayFunctionLikeReturnTypeHints = true,
							},
						},
						javascript = {
							inlayHints = {
								includeInlayParameterNameHints = "all",
								includeInlayFunctionParameterTypeHints = true,
								includeInlayVariableTypeHints = true,
								includeInlayPropertyDeclarationTypeHints = true,
								includeInlayFunctionLikeReturnTypeHints = true,
							},
						},
					},
				},
				tailwindcss = {},
				html = {},
				cssls = {},
				jsonls = {},
				lua_ls = {
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
				},
			}

			-- Setup all LSP servers
			for server, config in pairs(servers) do
				config.capabilities = capabilities
				require("lspconfig")[server].setup(config)
			end

			-- LSP keybindings
			vim.api.nvim_create_autocmd("LspAttach", {
				group = vim.api.nvim_create_augroup("lsp-attach", { clear = true }),
				callback = function(event)
					local map = function(keys, func, desc)
						vim.keymap.set("n", keys, func, { buffer = event.buf, desc = "LSP: " .. desc })
					end

					local builtin = require("telescope.builtin")
					map("gd", builtin.lsp_definitions, "Goto Definition")
					map("gr", builtin.lsp_references, "Goto References")
					map("gI", builtin.lsp_implementations, "Goto Implementation")
					map("gt", builtin.lsp_type_definitions, "Type Definition")
					map("<leader>ds", builtin.lsp_document_symbols, "Document Symbols")
					map("<leader>ws", builtin.lsp_dynamic_workspace_symbols, "Workspace Symbols")
					map("<leader>rn", vim.lsp.buf.rename, "Rename")
					map("<leader>ca", vim.lsp.buf.code_action, "Code Action")
					map("gh", vim.lsp.buf.hover, "Hover Documentation")
					map("gD", vim.lsp.buf.declaration, "Goto Declaration")

					-- Ctrl+Space for code actions
					vim.keymap.set(
						{ "n", "v" },
						"<C-Space>",
						vim.lsp.buf.code_action,
						{ buffer = event.buf, desc = "LSP: Code Action" }
					)

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
		end,
	},

	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			delay = 1000,
		},
	},

	-- Autocompletion
	{
		"hrsh7th/nvim-cmp",
		event = "InsertEnter",
		dependencies = {
			{
				"L3MON4D3/LuaSnip",
				build = "make install_jsregexp",
				dependencies = { "rafamadriz/friendly-snippets" },
			},
			"saadparwaiz1/cmp_luasnip",
			"hrsh7th/cmp-nvim-lsp",
			"hrsh7th/cmp-buffer",
			"hrsh7th/cmp-path",
		},
		config = function()
			local cmp = require("cmp")
			local luasnip = require("luasnip")

			require("luasnip.loaders.from_vscode").lazy_load()

			cmp.setup({
				snippet = {
					expand = function(args)
						luasnip.lsp_expand(args.body)
					end,
				},
				completion = {
					completeopt = "menu,menuone,noinsert",
					keyword_length = 2, -- Start completing after 2 characters
				},
				performance = {
					debounce = 150, -- Delay before showing completions (ms)
					throttle = 60, -- Throttle completion requests
				},
				mapping = cmp.mapping.preset.insert({
					["<C-n>"] = cmp.mapping.select_next_item(),
					["<C-p>"] = cmp.mapping.select_prev_item(),
					["<C-b>"] = cmp.mapping.scroll_docs(-4),
					["<C-f>"] = cmp.mapping.scroll_docs(4),
					["<C-Space>"] = cmp.mapping.complete(),
					["<C-e>"] = cmp.mapping.abort(),
					["<CR>"] = cmp.mapping.confirm({ select = true }),
					["<Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_next_item()
						elseif luasnip.expand_or_locally_jumpable() then
							luasnip.expand_or_jump()
						else
							fallback()
						end
					end, { "i", "s" }),
					["<S-Tab>"] = cmp.mapping(function(fallback)
						if cmp.visible() then
							cmp.select_prev_item()
						elseif luasnip.locally_jumpable(-1) then
							luasnip.jump(-1)
						else
							fallback()
						end
					end, { "i", "s" }),
				}),
				sources = {
					{ name = "nvim_lsp" },
					{ name = "luasnip" },
					{ name = "buffer" },
					{ name = "path" },
				},
			})
		end,
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
			},
			-- format_on_save = {
			-- 	timeout_ms = 500,
			-- },
			-- lsp_fallback = true,
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
		},
	},

	-- Tab/Buffer line
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		config = function()
			local bufferline = require("bufferline")

			local options = {
				numbers = "ordinal",
				diagnostics = "nvim_lsp",
				style_preset = {
					bufferline.style_preset.no_italic,
					bufferline.style_preset.no_bold,
				},
				offsets = {
					{
						filetype = "NvimTree",
						text = "File Explorer",
						text_align = "right",
						separator = true,
					},
				},
			}

			bufferline.setup({ options = options })

  vim.keymap.set("n", "<leader>[", function() bufferline.BufferLineCyclePrev() end, { desc = "Previous tab" })
  vim.keymap.set("n", "<leader>]", function() bufferline.BufferLineCycleNext() end, { desc = "Next tab" })
  vim.keymap.set("n", "<leader>1", function() bufferline.go_to(1, true) end, { desc = "Go to buffer 1",
  silent = true })
  vim.keymap.set("n", "<leader>2", function() bufferline.go_to(2, true) end, { desc = "Go to buffer 2",
  silent = true })
  vim.keymap.set("n", "<leader>3", function() bufferline.go_to(3, true) end, { desc = "Go to buffer 3",
  silent = true })
  vim.keymap.set("n", "<leader>4", function() bufferline.go_to(4, true) end, { desc = "Go to buffer 4",
  silent = true })
  vim.keymap.set("n", "<leader>5", function() bufferline.go_to(5, true) end, { desc = "Go to buffer 5",
  silent = true })
  vim.keymap.set("n", "<leader>6", function() bufferline.go_to(6, true) end, { desc = "Go to buffer 6",
  silent = true })
  vim.keymap.set("n", "<leader>7", function() bufferline.go_to(7, true) end, { desc = "Go to buffer 7",
  silent = true })
  vim.keymap.set("n", "<leader>8", function() bufferline.go_to(8, true) end, { desc = "Go to buffer 8",
  silent = true })
  vim.keymap.set("n", "<leader>9", function() bufferline.go_to(-1, true) end, { desc = "Go to last buffer",
  silent = true })
		end,
	},
	{
		"nvim-tree/nvim-tree.lua",
		version = "*",
		lazy = false,
		dependencies = {
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			require("nvim-tree").setup({
				view = {
					side = "right",
				},
			})
		end,
	},
})

-- Editor settings
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.wrap = true
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
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

vim.diagnostic.config({ update_in_insert = true })



-- Close floating windows (like hover docs) and clear search highlight on Escape
vim.keymap.set("n", "<Esc>", function()
	-- Close floating windows
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			vim.api.nvim_win_close(win, false)
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

-- Better paste
vim.keymap.set("x", "<leader>p", '"_dP')

-- File explorer toggle
local function toggle_explorer()
	local current_buf = vim.api.nvim_get_current_buf()
	local buf_name = vim.api.nvim_buf_get_name(current_buf)

	if string.match(buf_name, "^.*/$") or vim.bo[current_buf].filetype == "netrw" then
		vim.cmd("bd")
	else
		vim.cmd("Ex")
	end
end

vim.keymap.set("n", "<leader>e", vim.cmd.NvimTreeToggle, { desc = "Toggle file explorer" })

-- Telescope keymaps
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Find buffers" })
vim.keymap.set("n", "<leader>fh", builtin.help_tags, { desc = "Help tags" })
vim.keymap.set("n", "<leader>fr", builtin.oldfiles, { desc = "Recent files" })

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
vim.keymap.set("n", "ge", vim.diagnostic.open_float, { desc = "Show diagnostic under cursor" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostic quickfix list" })

-- Format buffer
vim.keymap.set("n", "<leader>fp", function()
	require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format buffer" })

-- Toggle line wrap
vim.keymap.set("n", "za", function()
	vim.wo.wrap = not vim.wo.wrap
	if vim.wo.wrap then
		print("Line wrap enabled")
	else
		print("Line wrap disabled")
	end
end, { desc = "Toggle line wrap" })



-- Terminal mode escape
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})
