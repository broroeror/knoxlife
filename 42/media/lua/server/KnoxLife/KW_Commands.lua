--- Server side of the admin right-click actions.
---
--- Spawning cannot happen on a multiplayer client. The guard and its full
--- diagnosis live at KW_Reseed.lua:64 -- briefly, an animal created client-side
--- renders and walks but can never be hurt, because only the server allocates
--- the network id a hit packet needs, so every swing is dropped server-side with
--- "The packet PlayerHitAnimal is not consistent". That is silent in game and
--- looks exactly like an animal that will not take damage.
---
--- So the client asks (KW_AdminMenu.lua) and the server acts, here.

-- The house binding, and it matters. This file used to open with
-- `if not KW then KW = {} end`, which creates a BARE GLOBAL called KW that has
-- no relationship to KnoxLife -- so KW.spawnOne and KW.pickBreed (defined on
-- KnoxLife in KW_Reseed.lua) were both nil here, every spawn silently missed,
-- and KnoxLife.spawnJuvenilesAt never existed for the debug menu to find. It
-- was the only file in the mod that bound KW differently.
KnoxLife = KnoxLife or {}
local KW = KnoxLife

local JUVENILES = {
    { id = "kwc_foxkit",       label = "fox kit" },
    { id = "kwc_coyotepup",    label = "coyote pup" },
    { id = "kwc_bobcatkitten", label = "bobcat kitten" },
    { id = "kwc_squirrelkit",  label = "squirrel kit" },
}

--- Spawn one of each juvenile around (x, y). Returns placed, list-of-failures.
---
--- Exposed on KW rather than kept local so a singleplayer game and the offline
--- Lua tests can call the same code path the server command uses. There is no
--- second implementation of this to drift.
function KW.spawnJuvenilesAt(x, y)
    local placed, missed = 0, {}
    for i, j in ipairs(JUVENILES) do
        -- Two tiles apart, so all four are visible at once and can be compared
        -- against each other and against any adult that wanders in.
        local breed = KW.pickBreed and KW.pickBreed(j.id, nil) or nil
        if KW.spawnOne and KW.spawnOne(j.id, breed, x + (i * 2), y) then
            placed = placed + 1
        else
            missed[#missed + 1] = j.label
        end
    end
    return placed, missed
end

local function onClientCommand(module, command, player, args)
    if module ~= "KnoxLife" then return end
    if command ~= "spawnJuveniles" then return end

    -- Re-check server-side. The client menu is already admin-gated, but a
    -- client command is just a packet and anyone can send one; a spawn command
    -- that trusts the sender is a cheat vector in a public mod.
    -- Compared lowercase, because that is what the game returns: every real
    -- access-level comparison in vanilla is `getAccessLevel() == "admin"`, and
    -- every capitalised "Admin" in vanilla is a UI label. Checking for "Admin"
    -- refused a genuine admin, and the refusal line said "non-admin admin",
    -- which read as nonsense. Fold the case and PRINT THE LEVEL, so the log says
    -- what actually failed instead of needing a code read to find out.
    if player and player.getAccessLevel then
        local lvl = string.lower(tostring(player:getAccessLevel() or ""))
        if lvl ~= "admin" and lvl ~= "moderator" then
            print("[KnoxLife] refused spawnJuveniles from "
                  .. tostring(player:getUsername())
                  .. " -- access level '" .. lvl .. "'")
            return
        end
    end
    if not (args and args.x and args.y) then return end

    local placed, missed = KW.spawnJuvenilesAt(args.x, args.y)
    print(string.format("[KnoxLife] spawnJuveniles by %s at %d,%d -- %d/%d placed%s",
        tostring(player and player:getUsername() or "?"),
        math.floor(args.x), math.floor(args.y), placed, #JUVENILES,
        #missed > 0 and (" -- failed: " .. table.concat(missed, ", ")) or ""))
end

Events.OnClientCommand.Add(onClientCommand)
