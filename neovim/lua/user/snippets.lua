local ls = require("luasnip")
-- some shorthands...
local s = ls.snippet
local sn = ls.snippet_node
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local c = ls.choice_node
local d = ls.dynamic_node
local r = ls.restore_node
local l = require("luasnip.extras").lambda
local rep = require("luasnip.extras").rep
local p = require("luasnip.extras").partial
local m = require("luasnip.extras").match
local n = require("luasnip.extras").nonempty
local dl = require("luasnip.extras").dynamic_lambda
local fmt = require("luasnip.extras.fmt").fmt
local fmta = require("luasnip.extras.fmt").fmta
local types = require("luasnip.util.types")
local conds = require("luasnip.extras.conditions")
local conds_expand = require("luasnip.extras.conditions.expand")

-- taken from https://github.com/L3MON4D3/LuaSnip/blob/master/Examples/snippets.lua

ls.add_snippets("vba", {

    s("event_procedure", {
        c(1, {
            t("AfterInsert"),
            t("AfterUpdate"),
            t("BeforeUpdate"),
            t("OnChange"),
            t("OnClick"),
            t("OnClose"),
            t("OnCurrent"),
            t("OnDblClick"),
            t("OnDelete"),
            t("OnEnter"),
            t("OnExit"),
            t("OnKeyDown"),
            t("OnKeyPress"),
            t("OnLoad"),
            t("OnMouseMove"),
            t("OnMouseWheel"),
            t("OnOpen"),
            t("OnUnload"),
        }),
        t(" =\"[Event Procedure]\""),
    }),

})
