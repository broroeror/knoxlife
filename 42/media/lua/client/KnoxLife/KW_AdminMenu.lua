--- Right-click "spawn the juveniles here", for admins on a server.
---
--- WHY THIS EXISTS RATHER THAN A DEBUG-MENU BUTTON
---
--- Every art change has to be confirmed by eye before it ships (KNOWN-GOOD.md
--- records what happens when it is not), and juveniles are the one life stage
--- that cannot be got on demand -- they are rare in the wild, so "go and look at
--- a kit" was not something anyone could actually do.
---
--- The debug menu turned out to be the wrong vehicle for that. It needs the game
--- launched with -debug, which also switches on the debug right-click context
--- menu -- an enormous list that is, in practice, hard to get past. Asking
--- someone to enable a broken UI in order to check some art is not a workflow.
---
--- The admin context menu has none of those problems. AdminContextMenu.lua:23
--- gates on `isClient() and (isAdmin() or getAccessLevel() == "moderator")` and
--- nothing else: no -debug, no launch flag, and the ordinary right-click menu.
--- Both KnoxLife test servers are logged into as admin already.
---
--- It also fixes the thing the debug row could not. Spawning has to happen
--- server-side -- see the guard at KW_Reseed.lua:64, where an animal created on
--- a multiplayer client renders and walks but can never be hurt, because only
--- the server allocates the network id a hit packet needs. So the client asks
--- and the server acts, which is what the debug row was structurally unable to
--- do and why it hid itself in multiplayer.

require "KnoxLife/KW_DebugMenu"
require "KnoxLife/KW_Planner"
require "KnoxLife/KW_MapOverlay"

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KnoxLifeAdminMenu = KnoxLifeAdminMenu or {}

-- The four juvenile stage ids. Kept here rather than imported so this file
-- stands alone if the debug menu is ever dropped; they are also asserted
-- against the shipped definitions by tools/check_lua.sh.
local JUVENILES = {
    { id = "kwc_foxkit",       label = "fox kit" },
    { id = "kwc_coyotepup",    label = "coyote pup" },
    { id = "kwc_bobcatkitten", label = "bobcat kitten" },
    { id = "kwc_squirrelkit",  label = "squirrel kit" },
}

local function onSpawnJuveniles(square, playerObj)
    if not (square and playerObj) then return end
    sendClientCommand(playerObj, "KnoxLife", "spawnJuveniles",
                      { x = square:getX(), y = square:getY(), z = square:getZ() })
    if HaloTextHelper then
        HaloTextHelper.addGoodText(playerObj, "Asked the server for juveniles")
    end
end

function KnoxLifeAdminMenu.doMenu(player, context, worldobjects, test)
    -- KW.mayUseAdminTools, not isAdmin(). This used to gate on
    -- `isClient() and (isAdmin() or getAccessLevel() == "moderator")` and both
    -- options silently vanished on a server where the locator submenu -- same
    -- mod, same player, same right-click -- appeared fine. The locator had
    -- already been fixed to read getAccessLevel() directly; this had not, so the
    -- two disagreed. One shared check now, in KW_Core.
    if not KW.mayUseAdminTools() then return end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then return true end

    local square
    for _, v in ipairs(worldobjects) do
        square = v:getSquare()
        if square then break end
    end
    if not square then return end

    local playerObj = getSpecificPlayer(player)
    -- Spawning is the MP-only half: an animal created on a client renders and
    -- walks but can never be hurt, because only the server allocates the network
    -- id a hit packet needs (KW_Reseed.lua:64). So this asks the server, and only
    -- exists where there is one to ask.
    if isClient and isClient() then
        context:addOption("Knox: spawn one of each juvenile here", square,
                          onSpawnJuveniles, playerObj)
    end

    -- The planner is read-only, client-side, and needs no server round trip --
    -- it previews the maths, it does not apply anything. So it has no business
    -- being MP-only, and offering it in singleplayer saves needing -debug just
    -- to look at a table.
    if KW.Planner then
        context:addOption("Knox: population planner", nil,
                          function() KW.Planner.open(player) end)
    end

    -- The planner says how many, this says where. Same allocation, two views.
    if KW.MapOverlay then
        context:addOption("Knox: routes on the map", nil,
                          function() KW.MapOverlay.show(player) end)
    end
end

Events.OnFillWorldObjectContextMenu.Add(KnoxLifeAdminMenu.doMenu)

return KnoxLifeAdminMenu
