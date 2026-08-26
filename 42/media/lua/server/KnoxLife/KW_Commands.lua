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

-- group is the MIGRATION group id, which is where possibleBreed lives; id is
-- the life-stage id that actually gets spawned. They are not the same string
-- and the difference matters -- see breedFor below.
local JUVENILES = {
    { id = "kwc_foxkit",       group = "kwc_fox",      label = "fox kit" },
    { id = "kwc_coyotepup",    group = "kwc_coyote",   label = "coyote pup" },
    { id = "kwc_bobcatkitten", group = "kwc_bobcat",   label = "bobcat kitten" },
    { id = "kwc_squirrelkit",  group = "kwc_squirrel", label = "squirrel kit" },
}

-- Every stage our mods ship, for the per-species spawn menu. Adults included,
-- because "I cannot spawn a fox" needs to be reproducible through a code path
-- that LOGS, rather than through the vanilla debug menu that does not.
KW.STAGES = {
    { group = "kwc_fox",      label = "Fox",
      adult = "kwc_foxvixen",    male = "kwc_foxdog",      baby = "kwc_foxkit" },
    { group = "kwc_coyote",   label = "Coyote",
      adult = "kwc_coyotefemale", male = "kwc_coyotemale",  baby = "kwc_coyotepup" },
    { group = "kwc_bobcat",   label = "Bobcat",
      adult = "kwc_bobcatfemale", male = "kwc_bobcatmale",  baby = "kwc_bobcatkitten" },
    { group = "kwc_squirrel", label = "Squirrel",
      adult = "kwc_squirrelfemale", male = "kwc_squirrelmale", baby = "kwc_squirrelkit" },
}

--- The breed to spawn a stage with.
--
-- ⚠️ Do not pass nil. addAnimal accepts it and then AnimalData picks for itself,
-- which threw `IndexOutOfBoundsException: Index 1 out of bounds for length 1`
-- for two of four juveniles while the other two spawned fine. Our species each
-- define exactly ONE breed, named "default", so there is nothing to gain from
-- letting the engine choose and a crash to lose.
--
-- Read from the migration group rather than hardcoded, so an addon species with
-- real breeds gets one of its own.
local function breedFor(stageId, groupId)
    local mg = MigrationGroupDefinitions and MigrationGroupDefinitions[groupId]
    local names = mg and mg.possibleBreed or "default"
    return KW.pickBreed and KW.pickBreed(stageId, names) or nil
end

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
        local breed = breedFor(j.id, j.group)
        if KW.spawnStageAt(j.id, j.group, x + (i * 2), y) then
            placed = placed + 1
        else
            missed[#missed + 1] = j.label
        end
    end
    return placed, missed
end

-- Animals spawned by an admin are HELD STILL until released.
--
-- ⚠️ Without this an admin spawn looks like a failure. Every species we ship is
-- `wild = true`, and vanilla's own comment on that flag says a wild animal
-- "will always flee humans" -- so one created at your feet bolts before you can
-- focus on it. The server logs "placed", nothing errors, and you see an empty
-- field. That is exactly what happened while testing the fox, and it is why the
-- juveniles were "never seen" for two days.
--
-- The whole point of spawning one is to LOOK at it, so it holds until told
-- otherwise. Never applied to the reseeder -- only to this menu.
local held = {}

local function holdStill(animal)
    if not animal then return end
    pcall(function() animal:getBehavior():setBlockMovement(true) end)
    held[#held + 1] = animal
end

--- Let every held animal go, and forget them.
function KW.releaseHeld()
    local n = 0
    for _, a in ipairs(held) do
        local ok = pcall(function() a:getBehavior():setBlockMovement(false) end)
        if ok then n = n + 1 end
    end
    held = {}
    return n
end

function KW.heldCount() return #held end

--- Spawn one named stage at a point, held still. Returns true if it placed.
function KW.spawnStageAt(stageId, groupId, x, y)
    local breed = breedFor(stageId, groupId)
    if not (KW.spawnOne and KW.spawnOne(stageId, breed, x, y)) then return false end
    -- spawnOne does not hand the animal back, so find what just arrived --
    -- and REPORT whether it is findable. `addToWorld()` returning without
    -- error is not proof the animal is on that square; an admin looking at an
    -- empty field needs to know which of the two happened, and until now the
    -- log said "placed" either way.
    local found = 0
    local sq = getCell and getCell():getGridSquare(x, y, 0)
    if not sq then
        KW.log(string.format("spawn %s: addAnimal succeeded but square %d,%d,0 "
            .. "is gone -- nothing to stand on", tostring(stageId), x, y))
        return true, 0
    end
    local list = sq.getAnimals and sq:getAnimals()
    local n = 0
    if list then pcall(function() n = list:size() end) end
    for i = 0, n - 1 do
        local a = list:get(i)
        local ok, t = pcall(function() return a:getAnimalType() end)
        if ok and tostring(t) == tostring(stageId) then
            holdStill(a)
            found = found + 1
        end
    end
    if found == 0 then
        KW.log(string.format("⚠️ spawn %s at %d,%d: addToWorld() reported success "
            .. "but the square holds %d animal(s) and none of them is one -- the "
            .. "animal is NOT where it was put", tostring(stageId), x, y, n))
    end
    return true, found
end

--- List every KnoxLife animal near a point. Answers "did it spawn or not?"
--- without guessing, which is the question that has cost the most time here.
function KW.nearbyReport(x, y, radius)
    radius = radius or 20
    local cell = getCell and getCell()
    if not cell then return {} end
    local out = {}
    for gx = math.floor(x - radius), math.floor(x + radius) do
        for gy = math.floor(y - radius), math.floor(y + radius) do
            local sq = cell:getGridSquare(gx, gy, 0)
            local list = sq and sq.getAnimals and sq:getAnimals()
            if list then
                local n = 0
                pcall(function() n = list:size() end)
                for i = 0, n - 1 do
                    local a = list:get(i)
                    local ok, t = pcall(function() return a:getAnimalType() end)
                    if ok and t then
                        local hp = -1
                        pcall(function() hp = a:getHealth() end)
                        out[#out + 1] = {
                            t = tostring(t),
                            d = math.sqrt((gx - x) ^ 2 + (gy - y) ^ 2),
                            hp = hp,
                        }
                    end
                end
            end
        end
    end
    table.sort(out, function(p, q) return p.d < q.d end)
    return out
end

--- Make the nearest predator attack the player.
--
-- This exists to answer the one open question in STATUS 7g -- whether goAttack
-- reaches a target we hand it -- without needing to survive a fight first. It
-- is also the only reliable way to SEE stage 1 aggression, which otherwise only
-- shows up when an animal is hurt and chooses not to flee.
function KW.provokeNearest(player, radius)
    if not player then return nil end
    radius = radius or 20
    local best, bestD
    local cell = getCell()
    if not cell then return nil end
    local px, py = player:getX(), player:getY()
    for x = math.floor(px - radius), math.floor(px + radius) do
        for y = math.floor(py - radius), math.floor(py + radius) do
            local sq = cell:getGridSquare(x, y, 0)
            local animals = sq and sq.getAnimals and sq:getAnimals()
            if animals then
                for i = 0, animals:size() - 1 do
                    local a = animals:get(i)
                    local t = a and a.getAnimalType and a:getAnimalType()
                    if t and string.find(tostring(t), "^kwc_") and not a:isDead() then
                        local d = (a:getX() - px) ^ 2 + (a:getY() - py) ^ 2
                        if not bestD or d < bestD then best, bestD = a, d end
                    end
                end
            end
        end
    end
    if not best then return nil end
    local ok, err = pcall(function() best:getBehavior():goAttack(player) end)
    if not ok then
        KW.log("provoke: goAttack refused this target -- " .. tostring(err))
        return nil
    end
    return tostring(best:getAnimalType()), math.sqrt(bestD)
end

local function onClientCommand(module, command, player, args)
    if module ~= "KnoxLife" then return end
    if command ~= "spawnJuveniles" and command ~= "spawnStage"
       and command ~= "provoke" and command ~= "release"
       and command ~= "nearby" then return end

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
    if command == "nearby" then
        local px, py = 0, 0
        pcall(function() px, py = player:getX(), player:getY() end)
        local list = KW.nearbyReport(px, py, 20)
        print(string.format("[KnoxLife] nearby for %s at %d,%d -- %d animal(s) within 20 tiles",
            tostring(player and player:getUsername() or "?"), px, py, #list))
        for i = 1, math.min(#list, 15) do
            print(string.format("[KnoxLife]    %-22s %5.1f tiles  hp=%.2f",
                list[i].t, list[i].d, list[i].hp))
        end
        return
    end

    if command == "release" then
        local n = KW.releaseHeld()
        print(string.format("[KnoxLife] released %d held animal(s) for %s", n,
            tostring(player and player:getUsername() or "?")))
        return
    end

    if command == "provoke" then
        local who, dist = KW.provokeNearest(player, 20)
        print(string.format("[KnoxLife] provoke by %s -- %s",
            tostring(player and player:getUsername() or "?"),
            who and string.format("%s at %.1f tiles told to attack", who, dist)
                or "no KnoxLife animal within 20 tiles"))
        return
    end

    if not (args and args.x and args.y) then return end

    if command == "spawnStage" then
        -- Validate against our own table. The admin check above already gates
        -- this, but a client command is just a packet and args.stage is a
        -- string the sender chose: without this the server would spawn any
        -- animal type it was asked for. Same reasoning as the access-level
        -- re-check -- a spawn command that trusts its arguments is a cheat
        -- vector in a public mod.
        local known = false
        for _, sp in ipairs(KW.STAGES) do
            if sp.group == args.group
               and (args.stage == sp.adult or args.stage == sp.male
                    or args.stage == sp.baby) then
                known = true
                break
            end
        end
        if not known then
            print(string.format("[KnoxLife] refused spawn of unknown stage '%s' in group '%s' from %s",
                tostring(args.stage), tostring(args.group),
                tostring(player and player:getUsername() or "?")))
            return
        end
        local ok, found = KW.spawnStageAt(args.stage, args.group, args.x, args.y)
        print(string.format("[KnoxLife] spawn %s by %s at %d,%d -- %s",
            tostring(args.stage), tostring(player and player:getUsername() or "?"),
            math.floor(args.x), math.floor(args.y),
            (not ok) and "FAILED (see the reason logged above)"
                or ((found or 0) > 0 and "placed and confirmed on the square"
                                     or "CREATED BUT NOT ON THE SQUARE")))
        return
    end

    local placed, missed = KW.spawnJuvenilesAt(args.x, args.y)
    print(string.format("[KnoxLife] spawnJuveniles by %s at %d,%d -- %d/%d placed%s",
        tostring(player and player:getUsername() or "?"),
        math.floor(args.x), math.floor(args.y), placed, #JUVENILES,
        #missed > 0 and (" -- failed: " .. table.concat(missed, ", ")) or ""))
end

Events.OnClientCommand.Add(onClientCommand)
