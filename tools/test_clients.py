#!/usr/bin/env python3
"""Load RC-Translator on every WoW client (TOC -> Lua files, in order) and play
a short session: login, chat in several languages through the chat filters and
the Translated tab, a fight where Retail and WoW Forever hide chat text
(secret values), and the slash commands.

  pip install lupa
  python3 tools/test_clients.py            all clients
  python3 tools/test_clients.py retail     one client

Fails on any Lua error.
"""
import os
import sys

import lupa.luajit21 as lupa_mod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# flavor -> (TOC file, interface number)
CLIENTS = {
    "era": ("RC-Translator.toc", 11508),
    "tbc": ("RC-Translator.toc", 20505),
    "wrath": ("RC-Translator.toc", 30405),
    "titan": ("RC-Translator.toc", 38002),
    "cata": ("RC-Translator.toc", 40402),
    "mists": ("RC-Translator.toc", 50504),
    "retail": ("RC-Translator.toc", 120005),
    "forever": ("RC-Translator_Camelot.toc", 16001),
}

RUN = r"""
local ADDON = "RC-Translator"
NS = {}
local function loadFile(file)
	local f = assert(io.open(ADDON_DIR .. "/" .. file, "rb"), "missing file " .. file)
	local src = f:read("*a"); f:close()
	src = src:gsub("^\239\187\191", "")
	local fn, err = loadstring(src, "@" .. file)
	if not fn then error("LOAD " .. file .. ": " .. tostring(err)) end
	local ok, e = pcall(fn, ADDON, NS)
	if not ok then error("LOAD " .. file .. ": " .. tostring(e)) end
end
local function fire(ev, ...)
	for _, f in ipairs(ALLFRAMES) do
		local fn = f.scripts.OnEvent
		if fn and (not f.events or f.events[ev]) then
			local ok, err = pcall(fn, f, ev, ...)
			if not ok then error("EVENT " .. ev .. ": " .. tostring(err)) end
		end
	end
end
local function update(dt)
	local due = TIMERS
	TIMERS = {}
	for _, fn in ipairs(due) do
		local ok, err = pcall(fn)
		if not ok then error("timer: " .. tostring(err)) end
	end
	for i = 1, #ALLFRAMES do
		local f = ALLFRAMES[i]
		local fn = f.scripts.OnUpdate
		if fn and f.shown then
			local ok, err = pcall(fn, f, dt)
			if not ok then error("OnUpdate: " .. tostring(err)) end
		end
	end
end
local function step(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then error(label .. ": " .. tostring(err)) end
end
-- a chat message the way the game delivers it: filters first, then events
local function chat(ev, text, sender, ...)
	local args = { text, sender, ... }
	for _, fn in ipairs(FILTERS[ev] or {}) do
		local res = { pcall(fn, ChatFrame1, ev, unpack(args)) }
		if not res[1] then error("filter " .. ev .. ": " .. tostring(res[2])) end
		if res[2] == true then return end
		if res[3] ~= nil then args[1] = res[3] end
	end
	fire(ev, unpack(args))
end

for line in io.lines(ADDON_DIR .. "/" .. TOC_FILE) do
	line = line:gsub("\r", ""):gsub("^\239\187\191", ""):gsub("\\", "/")
	if line ~= "" and not line:match("^#") and line:match("%.lua$") then
		loadFile(line)
	end
end
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
for i = 1, 5 do NOW = NOW + 0.2; update(0.2) end

local lines = {
	{ "CHAT_MSG_SAY", "hola amigo, como estas?", "Pedro-Realm" },
	{ "CHAT_MSG_GUILD", "bonjour tout le monde", "Jean-Realm" },
	{ "CHAT_MSG_WHISPER", "hallo, kannst du mir helfen?", "Hans-Realm" },
	{ "CHAT_MSG_PARTY", "привет всем", "Ivan-Realm" },
	{ "CHAT_MSG_CHANNEL", "WTS 多少钱", "Li-Realm", "", "2. Trade - City", "", "", 0, 2, "Trade - City" },
	{ "CHAT_MSG_RAID", "hello everyone", "Bob-Realm" },
	{ "CHAT_MSG_SAY", "my own line", "Rob-Realm" },
}
for _, l in ipairs(lines) do step("chat " .. l[1], chat, unpack(l)) end
-- the filter decorates a readable line with the clickable [T]
local res = { FILTERS["CHAT_MSG_SAY"][1](ChatFrame1, "CHAT_MSG_SAY", "hola amigo", "Pedro-Realm") }
assert(type(res[2]) == "string" and res[2]:find("rctranslate", 1, true), "chat filter adds the [T] link")
update(0.2)

-- a fight: Retail and WoW Forever hide chat text and senders from addons
COMBAT = true
fire("PLAYER_REGEN_DISABLED")
for _, l in ipairs(lines) do
	local text, sender = l[2], l[3]
	if SECRET_CLIENT then text, sender = NEWSECRET(text), NEWSECRET(sender) end
	step("chat in combat " .. l[1], chat, l[1], text, sender, select(4, unpack(l)))
	if SECRET_CLIENT then
		local r = { FILTERS[l[1]][1](ChatFrame1, l[1], text, sender) }
		assert(r[2] == text, "a hidden line passes through untouched")
	end
end
if SECRET_CLIENT then
	step("hidden addon message", fire, "CHAT_MSG_ADDON", NEWSECRET("RCT"), NEWSECRET("x"), "PARTY", NEWSECRET("Bob"))
end
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
update(0.2)

local cmds = {}
for k in pairs(SlashCmdList) do cmds[#cmds + 1] = k end
table.sort(cmds)
for _, k in ipairs(cmds) do
	for _, arg in ipairs({ "", "help", "langs", "status", "on", "off", "on" }) do
		step("slash " .. k .. " " .. arg, SlashCmdList[k], arg)
		update(0.1)
	end
end
step("translate a line", SlashCmdList[cmds[1]] or function() end, "es hola amigo")
update(0.2)
"""


def run(flavor):
    toc, build = CLIENTS[flavor]
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.ADDON_DIR = ROOT
    g.TOC_FILE = toc
    g.BUILD_TOC = build
    g.FLAVOR = flavor
    g.CLASS_FILE = "MAGE"
    g.CLASS_ID = 8
    L.execute(open(os.path.join(ROOT, "tools", "wow_env.lua"), encoding="utf-8").read())
    L.execute(RUN)


def main():
    flavors = sys.argv[1:] or list(CLIENTS)
    failed = 0
    for flavor in flavors:
        toc = CLIENTS[flavor][0]
        if not os.path.exists(os.path.join(ROOT, toc)):
            failed += 1
            print("FAIL %-7s no %s" % (flavor, toc))
            continue
        try:
            run(flavor)
            print("OK   %-7s" % flavor)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("FAIL %-7s %s" % (flavor, str(e).split("\nstack traceback")[0][:600]))
    print("ALL PASS" if not failed else "%d FAILED" % failed)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
