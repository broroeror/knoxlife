-- Knox Life -- populations that maintain themselves.
--
-- THE PROBLEM. Hunt an area out and it stays hunted out for the rest of the
-- save. Three engine facts combine to cause it, each verified rather than
-- assumed:
--
--   * AnimalZones.spawnAnimalsOnZone fires ONCE per zone, gated by a
--     `spawnedAnimals` flag.
--   * That flag is unreachable. AnimalZone exposes no accessor for it and the
--     owning class is not exposed to Lua: probed on a live server,
--     type(AnimalZones) is nil and getInstance() throws.
--   * VirtualAnimal, the off-screen state animals spend nearly all their
--     existence in, only moves, eats and sleeps. It cannot breed.
--
-- The game genuinely does have aging, geriatric decline, mating seasons,
-- pregnancy timers and minAgeForBaby. All of it only runs for animals in a
-- loaded chunk with a player present, which is a vanishing fraction of the map
-- and of the time. So effective wild reproduction is close to zero.
--
-- WHAT THIS DOES NOT DO. It does not simulate breeding, and it does not age
-- animals out. Both already exist and work; duplicating them would fight them.
-- This restores only the missing piece: a population that trends back toward
-- what the habitat can support.
--
--     growth per hour  =  r * N * (1 - N/K)  +  m
--
--   K  carrying capacity, from the routes already registered in that cell times
--      the species' own group size. Growth stops dead at K, so nothing overruns.
--   r  logistic rate. Fastest at half capacity, zero AT capacity, and zero at
--      zero, which is what makes recovery from near-nothing genuinely slow.
--   m  immigration, animals wandering in from neighbouring ground. Small, and
--      the only reason zero is not permanent.
--
-- TIME IS ACCRUED, NOT TICKED. A cell is settled up when a player is standing in
-- it, against however many hours have passed since it was last visited. Coming
-- back to a valley after three weeks applies three weeks of recovery at once.
-- That is both more correct than ticking only where somebody happens to be
-- standing, and far cheaper than ticking 4,065 cells forever.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

KW.POP = {
    -- Per in-game hour. 0.1/day takes a half-empty cell to about 95% of what it
    -- holds in roughly four in-game weeks.
    R_PER_HOUR = 0.1 / 24.0,

    -- Animals per hour wandering in from off the edge of the cell. One every ten
    -- days, which sounds negligible and is the entire reason a wiped-out cell
    -- behaves differently from a thinned one.
    --
    -- This started at one every two days and that was far too generous: measured,
    -- an empty cell reached 49 of 100 in four weeks while a half-empty one gained
    -- 50, so recolonising was no slower than topping up and the logistic term was
    -- decoration. At this rate an empty cell takes roughly two and a half times
    -- as long to refill as a half-empty one, which is the intended shape.
    IMMIGRATION_PER_HOUR = 0.1 / 24.0,

    -- Never settle up more than this in one go. A save left for a year should
    -- not compute a year of growth, and it does not need to: anything past a
    -- couple of months has already converged on K.
    MAX_CATCHUP_HOURS = 24 * 60,

    -- Animals appear at least this far from every player. Watching a deer wink
    -- into existence would undo the whole illusion.
    MIN_SPAWN_DIST = 40,

    -- And no further than this, because addAnimal needs a loaded square.
    MAX_SPAWN_DIST = 110,

    -- Per species per settle-up. Stops a long absence from emptying the pool
    -- into one clearing.
    MAX_PLACE_PER_VISIT = 6,
}

-- The cell grid the whole population model is expressed in. PUBLIC on purpose:
-- capacityIn, censusIn and settleCell all take cell coordinates, so without a
-- way to turn world coordinates into them, every one of those is unreachable
-- from outside this file -- which made the population model look public and
-- behave private. An addon doing its own carrying-capacity simulation (a
-- faction, a camp, anything that is not an animal) needs exactly these two.
KW.CELL = 300
local CELL = KW.CELL

--- World coordinates -> the population cell containing them.
-- @return cx, cy
function KW.cellOf(x, y)
    return math.floor(x / CELL), math.floor(y / CELL)
end

local cellOf = KW.cellOf

local function store()
    local md = ModData.getOrCreate("KnoxLife_pop")
    md.cells = md.cells or {}
    return md.cells
end

local function worldHours()
    local gt = getGameTime and getGameTime()
    if not gt then return 0 end
    local ok, h = pcall(function() return gt:getWorldAgeHours() end)
    return (ok and tonumber(h)) or 0
end

-- KW.meanGroupSize lives in KW_Core now: allocateRoutes needs it to turn a
-- density into a route count, and the client's locator calls allocateRoutes.

--- Carrying capacity per species for one cell: its routes times its group size.
--
-- Falls out of work already done, so Wildlife Density and Species Mix keep
-- meaning exactly what they mean, and an addon's species is included the moment
-- it registers.
function KW.capacityIn(cx, cy)
    local out = {}
    for _, part in ipairs(KW.allocateRoutes()) do
        local pool = KW.Routes and KW.Routes[part.pool]
        if pool then
            local routes = 0
            for i = part.first, math.min(part.first + part.count - 1, #pool) do
                local f = pool[i] and pool[i].follow
                if f and #f >= 2 then
                    local rx, ry = cellOf(f[1], f[2])
                    if rx == cx and ry == cy then routes = routes + 1 end
                end
            end
            if routes > 0 then
                out[part.species] = (out[part.species] or 0)
                    + (routes * KW.meanGroupSize(part.species))
            end
        end
    end
    return out
end

--- Count living animals per species inside a cell.
--
-- Filtered by cell rather than trusted wholesale. getCell():getAnimals() is a
-- flat list and it is not settled whether it includes off-screen animals; by
-- binning on position that question stops mattering, because the answer is the
-- same either way.
function KW.censusIn(cx, cy)
    local out, total = {}, 0
    local cell = getCell and getCell()
    if not cell then return out, 0 end
    local ok, list = pcall(function() return cell:getAnimals() end)
    if not ok or not list then return out, 0 end

    local n = 0
    pcall(function() n = list:size() end)
    for i = 0, n - 1 do
        local a = list:get(i)
        if a then
            local okp, ax, ay = pcall(function() return a:getX(), a:getY() end)
            if okp and ax and ay then
                local acx, acy = cellOf(ax, ay)
                if acx == cx and acy == cy then
                    local okt, t = pcall(function() return a:getAnimalType() end)
                    if okt and t then
                        out[t] = (out[t] or 0) + 1
                        total = total + 1
                    end
                end
            end
        end
    end
    return out, total
end

-- A census counts ANIMAL TYPES ("doe", "buck", "fawn") while capacity is per
-- GROUP ("deer"), so one has to be mapped onto the other.
local function typesOf(species)
    local g = MigrationGroupDefinitions and MigrationGroupDefinitions[species]
    if not g then return {} end
    return { g.female, g.male, g.baby }
end

local function countFor(species, census)
    local n = 0
    for _, t in ipairs(typesOf(species)) do
        if t then n = n + (census[t] or 0) end
    end
    return n
end

-- Slow, Normal, Fast. Normal is the four-week figure the tooltip promises;
-- the others are half and double it, which keeps the shape and moves the pace.
KW.RECOVERY_SCALE = { 0.5, 1.0, 2.0 }

function KW.recoveryScale()
    return KW.pickFromScale(KW.RECOVERY_SCALE, "RecoveryRate", 2)
end

--- Apply dt hours of growth to N against capacity K. Pure arithmetic, tested.
--
-- Both terms matter and they do different jobs. The logistic term is zero at
-- zero, so a wiped-out cell cannot bootstrap from it; immigration is what makes
-- zero survivable, and it is deliberately small so recolonising is the slowest
-- thing that can happen. At capacity the logistic term is zero and the clamp
-- catches immigration, so nothing ever exceeds what the habitat supports.
function KW.grow(n, k, hours)
    if k <= 0 or hours <= 0 then return n end
    local P = KW.POP
    if hours > P.MAX_CATCHUP_HOURS then hours = P.MAX_CATCHUP_HOURS end
    local scale = KW.recoveryScale()
    local r = P.R_PER_HOUR * scale
    local m = P.IMMIGRATION_PER_HOUR * scale
    for _ = 1, math.floor(hours) do
        if n >= k then n = k break end
        n = n + (r * n * (1.0 - (n / k))) + m
    end
    if n > k then n = k end
    return n
end

local function placeNear(species, px, py, howMany)
    local P = KW.POP
    local placed = 0
    for _ = 1, howMany * 6 do            -- attempts, not placements
        if placed >= howMany then break end
        local ang = ZombRand(360) * math.pi / 180.0
        local dist = P.MIN_SPAWN_DIST
            + ZombRand(P.MAX_SPAWN_DIST - P.MIN_SPAWN_DIST)
        local x = math.floor(px + (math.cos(ang) * dist))
        local y = math.floor(py + (math.sin(ang) * dist))
        if KW.spawnAnimalOf(species, x, y) then placed = placed + 1 end
    end
    return placed
end

--- Settle one cell up, and place whatever it is short by. Returns placed, dt.
function KW.settleCell(cx, cy, px, py)
    if not KW.getOption("WildlifeRecovery", true) then return 0, 0 end

    local cells = store()
    local key = cx .. "," .. cy
    local rec = cells[key]
    local now = worldHours()
    local placed = 0

    local cap = KW.capacityIn(cx, cy)
    local census = KW.censusIn(cx, cy)

    if rec == nil then
        -- First sight of this cell. Fill straight to capacity, once, which is
        -- what makes installing the mod into an existing world work at all:
        -- those zones already fired and will never fire again. Census-gated, so
        -- anything already alive counts against the target and nothing stacks.
        rec = { t = now, n = {} }
        for species, k in pairs(cap) do
            local have = countFor(species, census)
            rec.n[species] = math.max(have, k)
            local short = math.floor(k - have)
            if short > 0 then
                placed = placed + placeNear(species, px, py,
                    math.min(short, KW.POP.MAX_PLACE_PER_VISIT))
            end
        end
        cells[key] = rec
        return placed, 0
    end

    local dt = now - (rec.t or now)
    if dt < 1 then return 0, dt end
    rec.t = now

    for species, k in pairs(cap) do
        -- Trust the census over the remembered figure: the player may have shot
        -- half of them since, and that is exactly the case this exists for.
        local have = countFor(species, census)
        local target = KW.grow(have, k, dt)
        rec.n[species] = target
        local short = math.floor(target - have)
        if short > 0 then
            placed = placed + placeNear(species, px, py,
                math.min(short, KW.POP.MAX_PLACE_PER_VISIT))
        end
    end
    return placed, dt
end

--- Remove animals the engine can never update, and say how many.
--
-- An animal whose type is not in AnimalDefinitions is permanently broken rather
-- than merely odd. IsoAnimal.init sets `adef` from AnimalDefinitions.getDef and
-- returns early when that is nil, so `adef` stays null and IsoAnimal.update
-- dereferences it on every single tick. Measured: 1508 NullPointerExceptions in
-- two and a half minutes from a handful of them, and they do not stop, because
-- nothing in the engine removes an animal for being unupdatable.
--
-- This is a janitor for damage already done. A bad fallback in populationTick
-- spawned these on 2026-08-14 and they are saved in chunk data, so they come
-- back every time that ground loads until something clears them out. The check
-- is exactly the one the engine itself makes, so anything removed here was
-- already an animal the engine had given up on.
-- Every early return here SAYS SO. The first version had three silent `return 0`
-- paths and was called through a bare pcall, so it could fail in four different
-- ways and produce exactly what a working sweep with nothing to do produces:
-- silence. It ran for 9,306 consecutive frames of NullPointerException on
-- 2026-08-15 without once indicating that it was not doing its job.
--
-- A janitor that cannot report why it did nothing is worse than no janitor,
-- because its presence in the file reads as the problem being handled.
function KW.sweepBrokenAnimals()
    if not (AnimalDefinitions and AnimalDefinitions.getDef) then
        KW.log("sweep: AnimalDefinitions.getDef is missing; cannot check animals")
        return 0
    end
    local cell = getCell and getCell()
    if not cell then
        KW.log("sweep: no cell yet; skipped")
        return 0
    end
    local ok, list = pcall(function() return cell:getAnimals() end)
    if not ok or not list then
        KW.log("sweep: cell:getAnimals() failed; skipped")
        return 0
    end

    local n = 0
    pcall(function() n = list:size() end)

    -- Collect first, delete second. Removing from the list being walked skips
    -- entries, which would leave half of them behind on every pass.
    local doomed = {}
    for i = 0, n - 1 do
        local a = list:get(i)
        if a then
            local def
            local okt, t = pcall(function() return a:getAnimalType() end)
            if okt and t then
                pcall(function() def = AnimalDefinitions.getDef(t) end)
            end
            if not def then doomed[#doomed + 1] = a end
        end
    end

    for _, a in ipairs(doomed) do
        pcall(function() a:removeFromWorld() end)
        pcall(function() a:delete() end)
    end
    if #doomed > 0 then
        KW.log(string.format(
            "removed %d animal(s) with no definition; they would have thrown "
            .. "on every tick", #doomed))
    end
    return #doomed
end

function KW.populationTick()
    -- Clients run this file too (see the note in KW_Reseed.spawnOne). Spawning
    -- is already blocked there, so this second check buys nothing in safety --
    -- it just stops every player's machine censusing its cell once an in-game
    -- hour to reach a decision it is not allowed to act on.
    if isClient and isClient() then return end

    -- The sweep runs BEFORE the WildlifeRecovery gate, deliberately.
    --
    -- It used to sit after it, which made removing animals that crash the server
    -- conditional on a setting about population growth. Those are not the same
    -- decision: an admin who turns recovery off is saying "stop adding animals",
    -- not "leave the ones that throw a NullPointerException on every tick". With
    -- recovery off, the janitor could never run at all.
    --
    -- Ordering against the census also matters: counting broken animals would
    -- make the habitat look fuller than it is and suppress replacements.
    local swept = select(2, pcall(KW.sweepBrokenAnimals))
    if type(swept) ~= "number" then
        KW.log("sweep: threw an error; broken animals may still be in the world")
    end

    if not KW.getOption("WildlifeRecovery", true) then return end
    local players = getOnlinePlayers and getOnlinePlayers()
    local seen = {}

    local function forPlayer(p)
        if not p then return end
        local cx, cy = cellOf(p:getX(), p:getY())
        local key = cx .. "," .. cy
        if seen[key] then return end       -- two players in one cell, settle once
        seen[key] = true
        local placed = KW.settleCell(cx, cy, p:getX(), p:getY())
        -- Always logged, not gated behind a debug switch. It used to read
        -- KW.getOption("Debug", false), and there is no "Debug" option declared
        -- in sandbox-options.txt, so the read could only ever return the
        -- fallback and this line was dead. That mattered: it is the one piece of
        -- evidence that installing the mod into an existing world does anything
        -- at all, and without it the honest answer to "is this working?" was
        -- "the cells are recorded, so presumably".
        --
        -- Not noisy. Placement happens on the first visit to a cell and then
        -- only while a population is recovering, capped at MAX_PLACE_PER_VISIT
        -- per species, so a settled server prints this rarely and a fresh one
        -- prints exactly the story an admin wants to read.
        if placed > 0 then
            KW.log(string.format("population: placed %d in cell %s", placed, key))
        end
    end

    if players and players:size() > 0 then
        for i = 0, players:size() - 1 do pcall(forPlayer, players:get(i)) end
    elseif not (isServer and isServer()) then
        -- Singleplayer only. getSpecificPlayer(0) is the local player, and a
        -- dedicated server does not have one.
        --
        -- ⚠️ DO NOT USE THIS AS A GENERAL FALLBACK. It used to run whenever no
        -- players were online, and on a dedicated server it returned something
        -- with coordinates that were not a player's. Measured 2026-08-15 on an
        -- EMPTY server: four settles in cells 4,4 then 35,x, 34,x and 33,x, all
        -- over the map, none of them anywhere a player had been. Note that
        -- IsoAnimal extends IsoPlayer in this engine, so "a player" is a much
        -- looser idea than it reads.
        --
        -- The animals that produced were broken. Each one NPE'd on every tick
        -- with "Cannot read field turnDelta because this.adef is null", which is
        -- IsoAnimal.init bailing early because AnimalDefinitions.getDef came
        -- back nil and leaving adef unset. 1508 of them in 2.5 minutes, on a
        -- server with nobody connected, and it stopped only because the process
        -- was restarted.
        --
        -- Doing nothing here is not a compromise, it is correct: with no player
        -- there are no loaded chunks, so there is nowhere to put an animal and
        -- nothing to recover for.
        pcall(forPlayer, getSpecificPlayer(0))
    end
end

if Events and Events.EveryHours then
    Events.EveryHours.Add(function() pcall(KW.populationTick) end)
end
