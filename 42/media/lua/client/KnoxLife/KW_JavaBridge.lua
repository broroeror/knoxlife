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
KW.java = KW.java or {
    attackAnimation = false,   -- a real lunge instead of walking into the target
    animationTuning = false,   -- per-species cadence (m_SpeedScale)
    smoothPursuit   = false,   -- continuous re-path instead of stop-start
    huntingSprint   = false,   -- sprint only while hunting, not always
    liveSettings    = false,   -- apply sandbox changes without a restart
}

local ZB = "ZombieBuddy"

--- "active" | "dormant" | "absent"
function KW.javaState()
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

    local msg = "ZombieBuddy is installed but not running, so KnoxLife's "
             .. "optional animation features are off. Point at its jar with a "
             .. "-javaagent launch option."
    KW.log(msg)
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
