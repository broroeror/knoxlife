--- Is the optional Java layer there, and does the player need telling?
---
--- THE FAILURE THIS EXISTS FOR
---
--- Our own server admin installed ZombieBuddy, missed a step, and did not know.
--- Nothing said so. The mod simply behaved as though the agent were absent,
--- which is indistinguishable from not having tried. That is the worst kind of
--- failure -- silently degraded, looks broken, nobody knows why -- and it costs
--- nothing to fix.
---
--- THREE STATES, AND ONLY ONE OF THEM TALKS
---
---   absent            the mod is not installed. SAY NOTHING. Somebody who has
---                     not asked for the Java layer should never be nagged
---                     about it; the core is meant to be complete on its own.
---   present, dormant  installed and the agent never started -- a half
---                     installation. THIS is the one worth a message, and the
---                     only one.
---   active            the agent is up. Features switch on and it stays quiet.
---
--- ⚠️ The jar does NOT have to live in the game's root directory, whatever the
--- installation guide says. Pointing at it from Steam launch options works,
--- and is both simpler and more durable -- a file inside the install directory
--- is removed by "verify integrity of game files" and can be clobbered by any
--- update, while a launch option survives both.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

--- Feature flags. Every one is FALSE until an addon turns it on, and every
--- caller must work with all of them false -- that is what "the core is
--- playable alone" means in code rather than in a document.
--- ⚠️ FILLED PER KEY, never `KW.java = KW.java or {...}`. This file is `client`
--- and KW_AnimSets is `shared`, so the other one may have created the table
--- already -- and a wholesale `or` would then keep its table and leave every
--- flag below unset. They would read as nil rather than false, which behaves
--- identically at `if not KW.java.x` and differently everywhere that iterates,
--- so `KW.javaMissing()` would quietly stop reporting them.
KW.java = KW.java or {}
local DEFAULTS = {
    attackAnimation = false,   -- a real lunge instead of walking into the target
    animationTuning = false,   -- per-species cadence (m_SpeedScale)
    smoothPursuit   = false,   -- continuous re-path instead of stop-start
    huntingSprint   = false,   -- sprint only while hunting, not always
    liveSettings    = false,   -- apply sandbox changes without a restart
    ownAnimSets     = false,   -- our own AnimSets + actiongroups, see KW_AnimSets
}
for name, value in pairs(DEFAULTS) do
    if KW.java[name] == nil then KW.java[name] = value end
end

local ZB = "ZombieBuddy"

--- Turn on exactly the capabilities OUR OWN JAR says it provides.
---
--- ⚠️ FAIL CLOSED, AND NOTE WHAT IS BEING ASKED. "ZombieBuddy is running" is
--- not evidence that anything of ours works -- ZombieBuddy without our plugin
--- patches nothing (KW_AnimSets says so). So the question is not "is the agent
--- up" but "did OUR jar load and what does it claim". `KnoxLifeJavaLoaded` is
--- a global published by com.knoxlife.zb.Main, so its presence proves four
--- things at once that each fail silently: mod.info declared the jar,
--- ZombieBuddy found it, javaPkgName matched, and the Lua exposure worked.
---
--- The jar reports capabilities as a comma list and ships EMPTY until a patch
--- has actually been verified, so a loaded jar still turns nothing on by
--- itself. That is deliberate: the flag must follow the feature, never the
--- other way round.
function KW.applyJavaCapabilities()
    local loaded = false
    pcall(function()
        loaded = KnoxLifeJavaLoaded and KnoxLifeJavaLoaded() or false
    end)
    if not loaded then return false, {} end

    -- ⚠️ WARM FIRST, THEN ASK. The jar reports `ownAnimSets` only once it has
    -- actually merged a mod action state, and nothing requests our groups
    -- until the animsets are live -- which waits on that very flag. Asking the
    -- Java side to request the mod groups itself settles the deadlock with
    -- evidence: if the patch works the merge happens and the capability is
    -- earned; if it does not, nothing is claimed and the core runs as before.
    pcall(function()
        if KnoxLifeWarmActionGroups then KnoxLifeWarmActionGroups() end
    end)

    local caps = ""
    pcall(function()
        caps = (KnoxLifeJavaCapabilities and KnoxLifeJavaCapabilities()) or ""
    end)

    local on = {}
    for name in tostring(caps):gmatch("[^,%s]+") do
        -- Only flags this mod actually declares. An unknown name is a version
        -- mismatch between jar and Lua, and silently inventing a flag for it
        -- would make javaMissing() stop reporting honestly.
        if KW.java[name] ~= nil then
            KW.java[name] = true
            on[#on + 1] = name
        else
            KW.log("java capability '" .. name .. "' is unknown to this build; ignored")
        end
    end
    -- Diagnostics the jar exposes, so "it did nothing" and "it errored" are
    -- distinguishable in the log without attaching a debugger.
    local merges, err = 0, ""
    pcall(function()
        merges = (KnoxLifeActionGroupMerges and KnoxLifeActionGroupMerges()) or 0
        err = (KnoxLifeJavaLastError and KnoxLifeJavaLastError()) or ""
    end)
    if merges > 0 then
        KW.log("action groups: merged " .. merges .. " mod state(s)")
    end
    if err ~= "" then
        KW.log("⚠️ java layer reported an error: " .. tostring(err))
    end

    -- Now that the flags are set, do the work they unlock. This is the only
    -- place it is safe: KW.animsetsActive() gates on ownAnimSets, which is only
    -- true because a merge actually happened.
    if KW.applyAnimSets then pcall(KW.applyAnimSets) end

    table.sort(on)
    KW.log("Java layer live; capabilities on: "
           .. (#on > 0 and table.concat(on, ", ") or "none yet"))
    return true, on
end

--- "active" | "dormant" | "absent"
function KW.javaState()
    -- OUR jar loading is the strongest claim available, and the one that
    -- matters: it means the plugin is live, not merely that the agent is.
    local ours = false
    pcall(function()
        ours = KnoxLifeJavaLoaded and KnoxLifeJavaLoaded() or false
    end)
    if ours then return "active" end

    -- The agent publishes a global. Nothing else does, so its presence is the
    -- only claim worth trusting that the layer is really running.
    if _G[ZB] ~= nil then return "active" end

    -- Installed but not running. getModInfoByID sees a mod that is present on
    -- disk, which a Workshop subscription guarantees, so this needs no
    -- filesystem access and no guess at an install path.
    local info
    pcall(function() info = getModInfoByID and getModInfoByID(ZB) end)
    if info then return "dormant" end

    return "absent"
end

--- Which advertised features are currently off. Empty when nothing is missing.
function KW.javaMissing()
    local off = {}
    for name, on in pairs(KW.java) do
        if not on then off[#off + 1] = name end
    end
    table.sort(off)
    return off
end

local told = false

--- Say something exactly once, and only in the state that deserves it.
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

-- ⚠️ ACTUALLY CALL IT. applyJavaCapabilities() shipped defined and uninvoked,
-- which is the quietest possible bug: the jar loads, the log says so, the
-- handshake exists, and every flag stays false forever because nothing asks.
--
-- Run at load AND on OnGameBoot. The plugin's main() runs before mod Lua (seen
-- in the log: "Java layer loaded" at line 116, "loading KnoxLife" at 121), so
-- file scope is normally enough -- but that ordering is ZombieBuddy's to change,
-- and a retry costs nothing. Guarded so the second call is silent rather than
-- logging the same line twice.
local applied = false
local function applyOnce()
    if applied then return end
    local live = KW.applyJavaCapabilities()
    if live then applied = true end
end
applyOnce()
if Events and Events.OnGameBoot then
    Events.OnGameBoot.Add(function() pcall(applyOnce) end)
end

if Events and Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(_, player)
        pcall(KW.reportJavaState, player)
    end)
end

return KW.java
