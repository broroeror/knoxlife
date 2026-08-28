--- Telling a PLAYER about a half-installed Java layer.
---
--- The capability handshake itself lives in shared/KnoxLife/KW_Java.lua, because
--- a dedicated server needs it too. This file is only the part that needs a
--- person to talk to.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

require "KnoxLife/KW_Java"

local ZB = "ZombieBuddy"

-- ⚠️ LOCAL, AND IN THIS FILE. The split left this in shared/ while the
-- function using it stayed here, which silently turned it into a GLOBAL:
-- it then survived the file being reloaded and the notice fired exactly
-- once per process instead of once per load. The test caught it.
local told = false

function KW.reportJavaState(player)
    if told then return end
    told = true
    local state = KW.javaState()

    if state == "absent" then
        -- Deliberately silent. See the header.
        return
    end

    if state == "active" then
        KW.log("ZombieBuddy is running; optional features may be enabled by an addon")
        return
    end

    -- ⚠️ Says the agent is not running, NOT that starting it enables anything.
    -- The extras need the KnoxLife Java addon too, and that is unreleased.
    local msg = "ZombieBuddy is installed but its agent is not running, so "
             .. "KnoxLife's optional extras are off. Point at its jar with a "
             .. "-javaagent launch option, BEFORE the -- in Steam's launch "
             .. "options."
    KW.log(msg)

    -- ⚠️ SHOW THE SAME PANEL, not halo text. KW_MainMenuNotice tracks "menu"
    -- and "game" separately and opens at most once for each, so this is a
    -- second showing rather than a duplicate.
    --
    -- Both are needed. The main menu is the only place a player can act on a
    -- LAUNCH OPTION, and on a server it is the only place they will see
    -- anything at all -- a client that cannot join never reaches here. But our
    -- Lua is not loaded when the menu first appears (mod Lua loads with the mod
    -- list), so the menu showing is not guaranteed, while in game we are
    -- certainly loaded.
    local panelled = false
    pcall(function()
        panelled = KW.showJavaNotice and KW.showJavaNotice("game")
    end)
    if panelled then return end

    -- Only reached if the panel could not open at all -- KW_MainMenuNotice
    -- missing, or the UI classes unavailable. Better than saying nothing.
    if player and HaloTextHelper then
        pcall(function() HaloTextHelper.addBadText(player, "ZombieBuddy installed but not running") end)
    end
    if player and player.Say then
        pcall(function() player:Say("[KnoxLife] " .. msg) end)
    end
end

if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(_, player)
        pcall(KW.reportJavaState, player)
    end)
end

return KW.java
