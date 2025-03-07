--[[
    file: Indent
    title: Formatting on the Fly
    summary: A set of instructions for Neovim to indent Neorg documents.
    ---
`core.esupports.indent` uses Norg's format to unambiguously determine
the indentation level for the current line.

The indent calculation is aided by [treesitter](@core.integrations.treesitter), which
means that the quality of indents is "limited" by the quality of the produced syntax tree,
which will get better and better with time.

To reindent a file, you may use the inbuilt Neovim `=` operator.
Indent levels are also calculated as you type, but may not be entirely correct
due to incomplete syntax trees (if you find any such examples, then file an issue!).
--]]

local module = neorg.modules.create("core.esupports.indent")

module.setup = function()
    return {
        requires = {
            "core.integrations.treesitter",
            "core.autocommands",
        },
    }
end

module.public = {
    indentexpr = function(buf, line, node)
        line = line or (vim.v.lnum - 1)
        node = node or module.required["core.integrations.treesitter"].get_first_node_on_line(buf, line)

        if not node then
            return 0
        end

        local indent_data = module.config.public.indents[node:type()] or module.config.public.indents._

        if not indent_data then
            return 0
        end

        local _, initial_indent = node:start()

        local indent = 0

        for _, modifier in ipairs(indent_data.modifiers or {}) do
            if module.config.public.modifiers[modifier] then
                local ret = module.config.public.modifiers[modifier](buf, node, line, initial_indent)

                if ret ~= 0 then
                    indent = ret
                end
            end
        end

        local line_len = (vim.api.nvim_buf_get_lines(buf, line, line + 1, true)[1] or ""):len()

        -- Ensure that the cursor is within the `norg` language
        local current_lang = vim.treesitter.get_parser(buf, "norg"):language_for_range({
            line,
            line_len,
            line,
            line_len,
        })

        -- If it isn't then fall back to `nvim-treesitter`'s indent instead.
        if current_lang:lang() ~= "norg" then
            -- If we're in a ranged tag then apart from providing nvim-treesitter indents also make sure
            -- to account for the indentation level of the tag itself.
            if node:type() == "ranged_verbatim_tag_content" then
                local lnum = line
                local start = node:range()

                while lnum > start do
                    if vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, true)[1]:match("^%s*$") then
                        lnum = lnum - 1
                    else
                        return vim.fn["nvim_treesitter#indent"]()
                    end
                end

                return module.required["core.integrations.treesitter"].get_node_range(node:parent()).column_start
                    + vim.fn["nvim_treesitter#indent"]()
            else
                return vim.fn["nvim_treesitter#indent"]()
            end
        end

        -- Indents can be a static value, so account for that here
        if type(indent_data.indent) == "number" then
            -- If the indent is -1 then let Neovim indent instead of us
            if indent_data.indent == -1 then
                return -1
            end

            return indent + indent_data.indent + (module.config.public.tweaks[node:type()] or 0)
        end

        local calculated_indent = indent_data.indent(buf, node, line, indent, initial_indent) or 0

        if calculated_indent == -1 then
            return -1
        end

        return indent + calculated_indent + (module.config.public.tweaks[node:type()] or 0)
    end,
}

module.config.public = {
    -- The table of indentations.
    --
    -- This table describes a set of node types and how they should be indented
    -- when encountered in the syntax tree.
    --
    -- It also allows for certain nodes to be given properties (modifiers), which
    -- can additively stack indentation given more complex circumstances.
    indents = {
        -- Default behaviour for every other node not explicitly defined.
        _ = {
            modifiers = { "under-headings" },
            indent = 0,
        },

        -- Indent behaviour for paragraph segments (lines of text).
        ["paragraph_segment"] = {
            modifiers = { "under-headings", "under-nestable-detached-modifiers" },
            indent = 0,
        },

        -- Indent behaviour for strong paragraph delimiters.
        --
        -- The indentation of these should be determined based on the heading level
        -- that it is a part of. Since the `strong_paragraph_delimiter` node isn't actually
        -- a child of the previous heading in the syntax tree some extra work is required to
        -- make it indent as expected.
        ["strong_paragraph_delimiter"] = {
            indent = function(buf, _, line)
                local node = module.required["core.integrations.treesitter"].get_first_node_on_line(
                    buf,
                    vim.fn.prevnonblank(line) - 1
                )

                if not node then
                    return 0
                end

                return module.required["core.integrations.treesitter"].get_node_range(
                    node:type():match("heading%d") and node:named_child(1) or node
                ).column_start
            end,
        },

        -- Indent behaviour for headings.
        --
        -- In "idiomatic norg", headings should not be indented.
        ["heading1"] = {
            indent = 0,
        },

        -- Indent behaviour for headings.
        --
        -- In "idiomatic norg", headings should not be indented.
        ["heading2"] = {
            indent = 0,
        },

        -- Indent behaviour for headings.
        --
        -- In "idiomatic norg", headings should not be indented.
        ["heading3"] = {
            indent = 0,
        },

        -- Indent behaviour for headings.
        --
        -- In "idiomatic norg", headings should not be indented.
        ["heading4"] = {
            indent = 0,
        },

        -- Indent behaviour for headings.
        --
        -- In "idiomatic norg", headings should not be indented.
        ["heading5"] = {
            indent = 0,
        },

        -- Indent behaviour for headings.
        --
        -- In "idiomatic norg", headings should not be indented.
        ["heading6"] = {
            indent = 0,
        },

        ["ranged_tag"] = {
            modifiers = { "under-headings" },
            indent = 0,
        },

        -- Ranged tag contents' indentation should be calculated by Neovim itself.
        ["ranged_tag_content"] = {
            indent = -1,
        },

        -- `@end` tags should always be indented as far as the beginning `@` ranged verbatim tag.
        ["ranged_tag_end"] = {
            indent = function(_, node)
                return module.required["core.integrations.treesitter"].get_node_range(node:parent()).column_start
            end,
        },
    },

    -- Apart from indents, modifiers may also be defined.
    --
    -- These are repeatable instructions for nodes that share common traits.
    modifiers = {
        -- For any object that can exist under headings
        ["under-headings"] = function(_, node)
            local heading = module.required["core.integrations.treesitter"].find_parent(node:parent(), "heading%d")

            if not heading or not heading:named_child(1) then
                return 0
            end

            return module.required["core.integrations.treesitter"].get_node_range(heading:named_child(1)).column_start
        end,

        -- For any object that should be indented under a list
        ["under-nestable-detached-modifiers"] = function(_, node)
            local list = module.required["core.integrations.treesitter"].find_parent(node, {
                "unordered_list1",
                "unordered_list2",
                "unordered_list3",
                "unordered_list4",
                "unordered_list5",
                "unordered_list6",
                "ordered_list1",
                "ordered_list2",
                "ordered_list3",
                "ordered_list4",
                "ordered_list5",
                "ordered_list6",
                "quote1",
                "quote2",
                "quote3",
                "quote4",
                "quote5",
                "quote6",
            })

            if not list or not list:named_child(1) then
                return 0
            end

            if list:named_child(1):type() == "detached_modifier_extension" then
                return module.required["core.integrations.treesitter"].get_node_range(list:named_child(2)).column_start
                    + module.required["core.integrations.treesitter"]
                        .get_node_text(list:named_child(2))
                        :match("^%s*")
                        :len()
            end

            return module.required["core.integrations.treesitter"].get_node_range(list:named_child(1)).column_start
        end,
    },

    -- Tweaks are user defined `node_name` => `indent_level` mappings,
    -- allowing the user to overwrite the indentation level for certain nodes.
    tweaks = {},

    -- When true, will reformat the current line every time you press `<CR>` (Enter).
    format_on_enter = true,

    -- When true, will reformat the current line every time you press `<Esc>` (i.e. every
    -- time you leave insert mode).
    format_on_escape = true,
}

module.load = function()
    module.required["core.autocommands"].enable_autocommand("BufEnter")
end

module.on_event = function(event)
    if event.type == "core.autocommands.events.bufenter" and event.content.norg then
        vim.api.nvim_buf_set_option(
            event.buffer,
            "indentexpr",
            ("v:lua.neorg.modules.get_module('core.esupports.indent').indentexpr(%d)"):format(event.buffer)
        )

        local indentkeys = "o,O,*<M-o>,*<M-O>"
            .. neorg.lib.when(module.config.public.format_on_enter, ",*<CR>", "")
            .. neorg.lib.when(module.config.public.format_on_escape, ",*<Esc>", "")
        vim.api.nvim_buf_set_option(event.buffer, "indentkeys", indentkeys)
    end
end

module.events.subscribed = {
    ["core.autocommands"] = {
        bufenter = true,
    },
}

return module
