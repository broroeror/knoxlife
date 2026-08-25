-- Knox Life -- seed wildlife into a world that already existed.
--
-- THE PROBLEM THIS SOLVES. Animal zones carry a `spawnedAnimals` flag, and once
-- an area has been processed the game will not populate it again. So installing
-- this mod into a save you have already been playing leaves the ground you know
-- best conspicuously empty, and "start a new world" is a lot to ask of someone
-- three months into a character.
--
-- WHY IT IS NOT DONE BY CLEARING THAT FLAG. That was the obvious approach and it
-- is closed. `AnimalZone` holds the flag with no accessor of any kind, and the
-- class that owns the zones is not exposed to Lua at all: probed on a live
-- server, `type(AnimalZones)` is nil and `AnimalZones.getInstance()` throws
-- "attempted index: getInstance of non-table: null". There is no reaching it.
--
-- So this goes around it instead. `addAnimal` IS exposed, and vanilla uses it
-- server-side in ClientCommands.lua, so we place family groups directly on our
-- own registered routes and never involve the zone spawner. The animals are
-- ordinary animals afterwards; nothing about them is special-cased.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

-- Only ever seed ground that is actually loaded. addAnimal needs a real square,
-- and an animal placed into an unloaded chunk is at best wasted and at worst a
-- null dereference. This is why the command is "near me" rather than "the map".
KW.RESEED_RADIUS = 120

-- A hard ceiling per invocation, so a mistake costs you a clearing full of
-- rabbits rather than a save full of them.
KW.RESEED_MAX_GROUPS = 12

local function seededSet()
    local md = ModData.getOrCreate("KnoxLife_seeded")
    md.routes = md.routes or {}
    return md.routes
end

-- Pick one breed from the comma-separated list a species declares. Vanilla's own
-- spawn path resolves a breed by name and passes the object, not the string.
function KW.pickBreed(animalType, possibleBreed)
    if not (AnimalDefinitions and AnimalDefinitions.getDef) then return nil end
    local def = AnimalDefinitions.getDef(animalType)
    if not def then return nil end

    local names = {}
    for name in string.gmatch(tostring(possibleBreed or ""), "[^,]+") do
        names[#names + 1] = (string.gsub(name, "^%s*(.-)%s*$", "%1"))
    end
    if #names == 0 then return nil end
    local ok, breed = pcall(function()
        return def:getBreedByName(names[ZombRand(#names) + 1])
    end)
    return ok and breed or nil
end

-- The one place an animal is ever conjured. Shared with KW_Population, so both
-- the manual admin seed and the automatic recovery place animals identically
-- and there is a single thing to get right.
function KW.spawnOne(animalType, breed, x, y)
    -- ⚠️ NEVER ON A MULTIPLAYER CLIENT. This is the single choke point through
    -- which every animal this mod creates has to pass, so the guard lives here
    -- rather than only at the call sites.
    --
    -- Project Zomboid loads media/lua/server on CLIENTS TOO. That is not a
    -- mistake in how this mod is laid out; the directory is a convention, and
    -- `isServer()` is what actually separates the two. Confirmed from a client
    -- log: "[KnoxLife] registered 2107 routes ... as 6321 zones" was printed
    -- by the player's own machine while connected to a dedicated server.
    --
    -- An animal created here on a client exists on that client and nowhere else.
    -- It renders, it walks, and it can never be hurt, because only the server
    -- allocates the network id a hit packet needs: IsoAnimal.init guards its
    -- call to AnimalInstanceManager.allocateID on GameServer.server, so on a
    -- client the animal keeps IsoPlayer's constructor default of onlineId = 1.
    -- Every swing at it is then dropped server-side with "The packet
    -- PlayerHitAnimal is not consistent", which is silent in game and looks
    -- exactly like an animal that will not take damage. Diagnosed 2026-08-14
    -- from 67 rejected packets, all naming animal id 1.
    if isClient and isClient() then return false end

    local sq = getCell() and getCell():getGridSquare(x, y, 0)
    if not sq then return false end          -- chunk not loaded, skip quietly
    local ok, animal = pcall(function()
        return addAnimal(getCell(), x, y, 0, animalType, breed)
    end)
    if not ok or not animal then return false end
    local ok2 = pcall(function() animal:addToWorld() end)
    return ok2 and true or false
end
local spawnOne = KW.spawnOne

--- Place one animal of a SPECIES (a migration group), picking a sex sensibly.
--
-- Population recovery adds individuals rather than family groups, so it needs
-- this rather than seedGroup. Mostly females, because a population's ceiling is
-- set by how many of them there are and a map of lone bucks recovers nothing.
function KW.spawnAnimalOf(species, x, y)
    local g = MigrationGroupDefinitions and MigrationGroupDefinitions[species]
    if not g or not g.female then return false end
    local animalType = g.female
    if g.male and ZombRand(100) < 35 then animalType = g.male end
    return spawnOne(animalType, KW.pickBreed(animalType, g.possibleBreed), x, y)
end

--- Place one family group for `species` at (x, y), sized as the group defines.
--
-- Sizes come from MigrationGroupDefinitions rather than our own registry,
-- because that is the table the sandbox Group Size setting has already scaled.
-- minAnimal/maxAnimal count FEMALES; males and babies are added on top, which is
-- the same trap documented in KW_Groups.lua.
function KW.seedGroup(species, x, y)
    local g = MigrationGroupDefinitions and MigrationGroupDefinitions[species]
    if not g or not g.female then return 0 end

    local lo = tonumber(g.minAnimal) or 1
    local hi = tonumber(g.maxAnimal) or lo
    if hi < lo then hi = lo end
    local females = lo + ZombRand((hi - lo) + 1)
    local males = ZombRand((tonumber(g.maxMale) or 0) + 1)
    local babyPct = tonumber(g.babyChance) or 0

    local placed = 0
    local function scatter() return (x + ZombRand(9) - 4), (y + ZombRand(9) - 4) end

    for _ = 1, females do
        local sx, sy = scatter()
        if spawnOne(g.female, KW.pickBreed(g.female, g.possibleBreed), sx, sy) then
            placed = placed + 1
        end
        if g.baby and babyPct > 0 and ZombRand(100) < babyPct then
            local bx, by = scatter()
            if spawnOne(g.baby, KW.pickBreed(g.baby, g.possibleBreed), bx, by) then
                placed = placed + 1
            end
        end
    end
    for _ = 1, males do
        local sx, sy = scatter()
        if spawnOne(g.male, KW.pickBreed(g.male, g.possibleBreed), sx, sy) then
            placed = placed + 1
        end
    end
    return placed
end

local function midpointOf(flat)
    if not flat or #flat < 4 then return nil end
    local pairsN = math.floor(#flat / 2)
    local i = math.floor(pairsN / 2)
    return flat[(i * 2) + 1], flat[(i * 2) + 2]
end

--- Seed every registered route near (px, py) that has not been seeded before.
--
-- Returns placed, groups, skipped-as-already-done.
function KW.reseedNear(px, py, radius)
    radius = radius or KW.RESEED_RADIUS
    local seeded = seededSet()
    local placed, groups, already = 0, 0, 0

    for _, part in ipairs(KW.allocateRoutes()) do
        local pool = KW.Routes and KW.Routes[part.pool]
        if pool then
            for i = part.first, math.min(part.first + part.count - 1, #pool) do
                if groups >= KW.RESEED_MAX_GROUPS then break end
                local key = part.pool .. ":" .. i
                local mx, my
                if pool[i] then mx, my = midpointOf(pool[i].follow) end
                if mx and my then
                    local dx, dy = mx - px, my - py
                    if ((dx * dx) + (dy * dy)) <= (radius * radius) then
                        if seeded[key] then
                            already = already + 1
                        else
                            local n = KW.seedGroup(part.species, mx, my)
                            if n > 0 then
                                seeded[key] = true
                                placed = placed + n
                                groups = groups + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return placed, groups, already
end
