vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

vim.o.confirm = true

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
-- plugin start
require("lazy").setup({
	-- Colorscheme
	{
		"rebelot/kanagawa.nvim",
		lazy = false,
		priority = 1000,
		opts = {},
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
		dependencies = { "nvim-lua/plenary.nvim", { "nvim-telescope/telescope-fzf-native.nvim", build = "make" } },
		config = function()
			local h_pct = 0.90
			local w_pct = 0.80
			local w_limit = 75

			local standard_setup = {
				file_ignore_patterns = {
					"node_modules/*",
					".git/*",
				},
				borderchars = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
				layout_strategy = "vertical",
				layout_config = {
					vertical = {
						mirror = true,
						prompt_position = "top",
						width = function(_, cols, _)
							return math.min(math.floor(w_pct * cols), w_limit)
						end,
						height = function(_, _, rows)
							return math.floor(rows * h_pct)
						end,
						preview_cutoff = 10,
						preview_height = 0.4,
					},
				},
			}

			-- Function to generate config for grep and reference pickers
			local horizontal_preview_config = {
				layout_strategy = "horizontal",
				sorting_strategy = "ascending",
				layout_config = {
					horizontal = {
						height = 0.95,
						width = 0.95,
						preview_width = 0.50,
						prompt_position = "top",
						preview_cutoff = 0,
					},
				},
				path_display = { "filename_first" },
			}

			require("telescope").setup({
				defaults = vim.tbl_extend("error", standard_setup, {
					sorting_strategy = "ascending",
					path_display = { "filename_first" },
					mappings = {
						n = {
							["o"] = require("telescope.actions.layout").toggle_preview,
						},
						i = {
							["<C-o>"] = require("telescope.actions.layout").toggle_preview,
						},
					},
				}),

				pickers = {
					find_files = {
						hidden = true,
						preview = {
							hide_on_startup = true,
						},
						find_command = {
							"fd",
							"--type",
							"f",
							"-H",
							"--strip-cwd-prefix",
						},
					},
					live_grep = horizontal_preview_config,
					lsp_references = horizontal_preview_config,
					grep_string = horizontal_preview_config,
				},
				extensions = {
					fzf = {},
				},
			})

			require("telescope").load_extension("fzf")

			-- Enable wrap in telescope preview windows
			vim.api.nvim_create_autocmd("User", {
				pattern = "TelescopePreviewerLoaded",
				callback = function()
					vim.wo.wrap = true
				end,
			})
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

			-- Auto-install LSP servers
			require("mason-lspconfig").setup({
				ensure_installed = {
					"ts_ls",
					"tailwindcss",
					"html",
					"cssls",
					"jsonls",
					"lua_ls",
					"bashls",
				},
				automatic_installation = true,
			})

			-- LSP progress notifications
			require("fidget").setup({})

			-- Capabilities for completion
			local capabilities = vim.lsp.protocol.make_client_capabilities()

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
				tailwindcss = {
					settings = {
						tailwindCSS = {
							classFunctions = { "cva", "cx" },
							experimental = {
								classRegex = {
									-- Match: const ANYTHING_CLS = "tailwind classes here"
									-- { "\\w*_CN\\s*=\\s*['\"`]([^'\"`]*)['\"`]" },
									-- You can add more patterns as needed
								},
							},
						},
					},
				},
				html = {},
				cssls = {},
				jsonls = {},
				bashls = {},
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
					vim.keymap.set("n", "grr", builtin.lsp_references, { desc = "Goto References" })
					map("gI", builtin.lsp_implementations, "Goto Implementation")
					map("gt", builtin.lsp_type_definitions, "Type Definition")
					map("<leader>st", builtin.lsp_document_symbols, "Document Symbols")
					map("<leader>sT", builtin.lsp_dynamic_workspace_symbols, "Workspace Symbols")
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
		-- optional: provides snippets for the snippet source
		dependencies = { "rafamadriz/friendly-snippets" },

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

			-- Default list of enabled providers defined so that you can extend it
			-- elsewhere in your config, without redefining it, due to `opts_extend`
			sources = {
				default = { "lsp", "path", "snippets", "buffer" },
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
			},
			format_after_save = {
				lsp_format = "fallback",
			},
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
				end, { desc = "go to next buffer" })

				map("n", "[c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gitsigns.nav_hunk("prev")
					end
				end, { desc = "go to prev buffer" })

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
	-- Tab/Buffer line
	{
		"akinsho/bufferline.nvim",
		version = "*",
		dependencies = "nvim-tree/nvim-web-devicons",
		enabled = vim.g.open_mode ~= 1,
		config = function()
			local bufferline = require("bufferline")

			local options = {
				numbers = "ordinal",
				diagnostics = "nvim_lsp",
				diagnostics_indicator = function(_count, _level, diagnostics_dict, _context)
					local s = ""
					if diagnostics_dict.error then
						s = s .. " %#DiagnosticError#" .. diagnostics_dict.error .. "%*"
					end
					if diagnostics_dict.warning then
						s = s .. " %#DiagnosticWarn#" .. diagnostics_dict.warning .. "%*"
					end
					return s
				end,
				style_preset = {
					bufferline.style_preset.no_italic,
					bufferline.style_preset.no_bold,
				},
				offsets = {
					{
						filetype = "NeoTree",
						text = "File Explorer",
						text_align = "right",
						separator = true,
					},
				},
			}

			bufferline.setup({
				options = options,
			})

			-- Terminal mode escape
			vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { desc = "Exit terminal mode" })

			local function close_all_buffers()
				for _, e in ipairs(bufferline.get_elements().elements) do
					vim.schedule(function()
						vim.cmd("bd " .. e.id)
					end)
				end
			end

			vim.keymap.set("n", "<leader>ba", close_all_buffers, { desc = "Close all buffers" })

			vim.keymap.set("n", "<leader>br", function()
				bufferline.close_in_direction("right")
			end, { desc = "Close buffers to the right" })

			vim.keymap.set("n", "<leader>bl", function()
				bufferline.close_in_direction("left")
			end, { desc = "Close buffers to the left" })

			vim.keymap.set("n", "<leader>w", function()
				local buf = vim.api.nvim_get_current_buf()
				-- vim.cmd("bp") -- go to previous buffer
				vim.cmd("bd " .. buf) -- delete the buffer we just left
			end, { desc = "Close buffer" })

			vim.keymap.set("n", "<leader>bo", bufferline.close_others, { desc = "Close other buffers" })

			vim.keymap.set("n", "<leader>]", ":BufferLineCycleNext<CR>", { silent = true, desc = "Go to next tab" })
			vim.keymap.set("n", "<leader>[", ":BufferLineCyclePrev<CR>", { silent = true, desc = "Go to previous tab" })

			vim.keymap.set("n", "<leader>1", function()
				bufferline.go_to(1, true)
			end, { desc = "Go to buffer 1", silent = true })

			vim.keymap.set("n", "<leader>2", function()
				bufferline.go_to(2, true)
			end, { desc = "Go to buffer 2", silent = true })
			vim.keymap.set("n", "<leader>3", function()
				bufferline.go_to(3, true)
			end, { desc = "Go to buffer 3", silent = true })
			vim.keymap.set("n", "<leader>4", function()
				bufferline.go_to(4, true)
			end, { desc = "Go to buffer 4", silent = true })
			vim.keymap.set("n", "<leader>5", function()
				bufferline.go_to(5, true)
			end, { desc = "Go to buffer 5", silent = true })
			vim.keymap.set("n", "<leader>6", function()
				bufferline.go_to(6, true)
			end, { desc = "Go to buffer 6", silent = true })
			vim.keymap.set("n", "<leader>7", function()
				bufferline.go_to(7, true)
			end, { desc = "Go to buffer 7", silent = true })
			vim.keymap.set("n", "<leader>8", function()
				bufferline.go_to(8, true)
			end, { desc = "Go to buffer 8", silent = true })
			vim.keymap.set("n", "<leader>9", function()
				bufferline.go_to(-1, true)
			end, { desc = "Go to last buffer", silent = true })
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
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99 -- Allow folds to be created
vim.opt.foldlevelstart = 99 -- Open all folds when opening a file
vim.opt.foldenable = true

vim.diagnostic.config({ update_in_insert = true })

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

vim.keymap.set("n", "<leader>e", function()
	local snacks = require("snacks.explorer")
	snacks.open()
end, { desc = "Toggle file explorer" })

vim.keymap.set("n", "-", "<cmd>Oil .<CR>", { desc = "Open Oil.nvim" })

-- Telescope keymaps
local builtin = require("telescope.builtin")
vim.keymap.set("n", "<leader>sf", builtin.find_files, { desc = "Find files" })
vim.keymap.set("n", "<leader>sg", builtin.live_grep, { desc = "Live grep" })
vim.keymap.set({ "n", "v" }, "<leader>su", builtin.grep_string, { desc = "Live grep" })
vim.keymap.set("n", "<leader>sb", builtin.buffers, { desc = "Find buffers" })
vim.keymap.set("n", "<leader>sh", builtin.help_tags, { desc = "Help tags" })
vim.keymap.set("n", "<leader>sr", builtin.oldfiles, { desc = "Recent files" })
vim.keymap.set("n", "<leader>sk", builtin.keymaps, { desc = "Search keymaps" })
vim.keymap.set("n", "<leader>sr", builtin.resume, { desc = "Search resume" })

-- Diagnostic keymaps
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous diagnostic" })
vim.keymap.set("n", "]d", vim.diagnostic.goto_next, { desc = "Next diagnostic" })
vim.keymap.set("n", "ge", vim.diagnostic.open_float, { desc = "Show diagnostic under cursor" })
vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, { desc = "Diagnostic quickfix list" })

-- Format buffer
vim.keymap.set("n", "<leader>fp", function()
	require("conform").format({ async = true, lsp_fallback = true })
end, { desc = "Format buffer" })

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking text",
	group = vim.api.nvim_create_augroup("highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

-- Auto-delete buffers opened via jump-to-definition when jumping back
local definition_jump_buffers = {}
local pending_definition_jump = false

-- Mark that we're about to do a definition jump
local function mark_definition_jump()
	pending_definition_jump = true
end

-- Track buffer if it was opened via definition jump
vim.api.nvim_create_autocmd("BufEnter", {
	group = vim.api.nvim_create_augroup("definition-jump-tracker", { clear = true }),
	callback = function(args)
		if pending_definition_jump then
			pending_definition_jump = false
			local bufnr = args.buf
			-- Only track if it's a real file buffer
			if vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= "" then
				definition_jump_buffers[bufnr] = true
			end
		end
	end,
})

-- Override gd to mark definition jumps (for Telescope LSP definitions)
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("definition-jump-keymap", { clear = true }),
	callback = function(event)
		vim.keymap.set("n", "gd", function()
			mark_definition_jump()
			require("telescope.builtin").lsp_definitions()
		end, { buffer = event.buf, desc = "LSP: Goto Definition (auto-cleanup)" })
	end,
})

-- Smart Ctrl-O that deletes definition-jump buffers when leaving them
vim.keymap.set("n", "<C-o>", function()
	local current_buf = vim.api.nvim_get_current_buf()
	local was_definition_jump = definition_jump_buffers[current_buf]

	-- Execute the normal Ctrl-O jump using feedkeys
	local ctrl_o = vim.api.nvim_replace_termcodes("<C-o>", true, false, true)
	vim.api.nvim_feedkeys(ctrl_o, "n", false)

	-- Use vim.schedule to check after the jump completes
	vim.schedule(function()
		local new_buf = vim.api.nvim_get_current_buf()
		if was_definition_jump and new_buf ~= current_buf then
			-- Check if buffer is still valid and not modified
			if vim.api.nvim_buf_is_valid(current_buf) and not vim.bo[current_buf].modified then
				pcall(vim.api.nvim_buf_delete, current_buf, { force = false })
			end
			definition_jump_buffers[current_buf] = nil
		end
	end)
end, { desc = "Jump back and cleanup definition buffers" })

vim.api.nvim_create_user_command("TermHl", function()
	local b = vim.api.nvim_create_buf(false, true)
	local chan = vim.api.nvim_open_term(b, {})
	vim.api.nvim_chan_send(chan, table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
	vim.api.nvim_win_set_buf(0, b)
end, { desc = "Highlights ANSI termcodes in curbuf" })
