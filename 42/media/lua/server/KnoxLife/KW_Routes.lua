-- Knox Life -- migration route registration.
--
-- This is the part that actually fixes the problem. Wild herds spawn along
-- "Animal" zones hand-placed in the map data, and the base map carries twenty
-- of them for the entire world -- which is why deer are rare, and why the herds
-- you do find are enormous: existing mods inflate the group instead of adding
-- groups.
--
-- Route geometry is baked offline by tools/gen_routes.py, which reads the biome
-- map PNGs the game already ships and picks forest and farmland edge. Doing it
-- offline means placement is deterministic, reviewable, and costs nothing at
-- load; all this file does is hand the polylines to the engine.
--
-- There is one baked pool PER SPECIES, not per size class. Rabbit, turkey and
-- raccoon used to share a single habitat model that suited none of them: a
-- rabbit avoids forest interior, a turkey wants mast hardwood near water, a
-- raccoon is a riparian animal with a tiny range. Measured on the generated
-- pools, the separation is real rather than nominal -- rabbit routes sit on 2%
-- forest against turkey's 93%, and raccoon routes sit a median 288 tiles from
-- water against rabbit's 762.
--
-- Each route registers three zones, mirroring exactly what the vanilla map data
-- does in media/lua/server/metazones/metazoneHandler.lua:
--   Follow -- the path the herd walks
--   Eat    -- a local feeding area
--   Sleep  -- a local bedding area
-- The Eat and Sleep zones matter more than they look. Vanilla has 45 feeding
-- and 34 bedding zones shared by every herd on the map, and almost none are
-- tagged for a species, so every group walks toward the same few spots. That
-- convergence is a second, quieter cause of the blobs.

KnoxLife = KnoxLife or {}
local KW = KnoxLife

local ZONE_TYPE = "Animal"
local Z_LEVEL = 0

local function registerPolyline(points, properties)
    local world = getWorld()
    if not world then return false end
    local grid = world:getMetaGrid()
    if not grid then return false end

    -- Vanilla animal zones are unnamed and carry no line width, so we match
    -- that exactly rather than inventing values the spawner might read.
    grid:registerGeometryZone("", ZONE_TYPE, Z_LEVEL, "polyline", points, properties)
    return true
end

local function registerRoute(route, animalType)
    local ok = registerPolyline(route.follow,
        { AnimalType = animalType, Action = "Follow" })
    if not ok then return 0 end

    local count = 1
    if route.eat and #route.eat >= 4 then
        registerPolyline(route.eat, { Action = "Eat" })
        count = count + 1
    end
    if route.sleep and #route.sleep >= 4 then
        registerPolyline(route.sleep, { Action = "Sleep" })
        count = count + 1
    end
    return count
end

function KW.registerRoutes()
    if KW._routesRegistered then
        return
    end

    -- ⚠️ `next` DOES NOT EXIST in Project Zomboid's Lua. Kahlua implements
    -- `pairs` natively without exposing the `next` it is normally built on, so
    -- `next(t)` compiles, passes every offline test under real Lua, and then
    -- throws "Object tried to call nil" on the server. Confirmed by logging
    -- type(next) from inside this function: it is nil while `pairs`, `ipairs`,
    -- `table.concat`, `table.sort`, `math.floor` and `math.min` are all fine.
    -- Use pairs for emptiness tests.
    local haveRoutes = false
    if KW.Routes then
        for _ in pairs(KW.Routes) do haveRoutes = true; break end
    end
    if not haveRoutes then
        KW.log("ERROR: baked route data missing (KW_RouteData.lua did not load)")
        return
    end

    -- Zones are typed with the SPECIES, not the size class. The engine reads
    -- AnimalType as a plain lookup into MigrationGroupDefinitions, so "turkey"
    -- resolves to the leaf definition and spawns turkeys directly; vanilla's own
    -- map data does the same with "deer" and "rabbit". A name with no definition
    -- logs a debug line and spawns nothing rather than crashing, which is quiet
    -- enough to be worth guarding here instead.
    local plan = KW.allocateRoutes()
    if #plan == 0 then
        KW.log("no species are enabled, so no routes were placed")
        KW._routesRegistered = true
        return
    end

    local zones, total = 0, 0
    local summary = {}

    for _, part in ipairs(plan) do
        local pool = KW.Routes[part.pool]
        if MigrationGroupDefinitions and MigrationGroupDefinitions[part.species] == nil then
            KW.log(string.format(
                "WARNING: no migration definition for '%s'; its %d routes would "
                .. "spawn nothing, so they are skipped",
                part.species, part.count))
        else
            -- The pool is ordered by a farthest-point traversal, so any slice of
            -- it stays spread across the map rather than bunching in one corner.
            for i = part.first, part.first + part.count - 1 do
                local n = registerRoute(pool[i], part.species)
                if n == 0 then
                    KW.log("ERROR: could not reach the metagrid; routes not placed")
                    return
                end
                zones = zones + n
            end
            total = total + part.count
            summary[#summary + 1] = string.format("%s %d", part.species, part.count)
        end
    end

    -- Report the shortfall, because it is real and permanent: rabbits and
    -- squirrels ask for several times the territories this map has the habitat
    -- for, and a number that just came out smaller would look like a bug.
    local short = {}
    for _, part in ipairs(plan) do
        if part.count < part.wanted then
            short[#short + 1] = string.format("%s %d of %d",
                part.species, part.count, part.wanted)
        end
    end

    -- Say which runtime this is, because this file registers on BOTH of them and
    -- for a long time nothing in the log said so. A player reading their own
    -- console saw "registered 2107 routes" and reasonably concluded they were
    -- looking at the server. Several behaviours turn on this distinction and one
    -- of them cost a play session, so it is worth four words.
    local role = "singleplayer"
    if isServer and isServer() then role = "server"
    elseif isClient and isClient() then role = "client" end

    KW._routesRegistered = true
    KW.log(string.format(
        "[%s] registered %d routes (%s) as %d zones -- %.0f%% of 1993 density, mix '%s'",
        role, total, table.concat(summary, ", "), zones,
        KW.realismFraction() * 100, KW.speciesMix().id))
    if #short > 0 then
        KW.log("the map has no room for all of it: " .. table.concat(short, ", ")
            .. " (habitat limit, not a setting)")
    end

    KW.rebuildJunctions()
end

-- Zones must be linked to each other by "junctions" before the animal
-- pathfinder will walk them. A zone that never gets one keeps a null junction
-- list, and VirtualAnimalState.moveAlongPath dereferences it every tick --
-- roughly a thousand NullPointerExceptions per minute, with the herd stuck.
--
-- This used to try to force a rebuild from Lua. **Do not put that back.** Both
-- access paths are dead -- `AnimalZones` is not exposed to Lua and
-- `getWorld():getAnimalZones()` does not exist -- so the attempt threw twice on
-- every boot, printed two ERROR lines, and then warned that "herds will not
-- path", which is false and alarming in a user's console.
--
-- No rebuild is needed. `addJunctionsWithOtherZone` matches points, not
-- proximity, and the generator emits each route's Eat and Sleep legs starting
-- from the *exact* vertex the Follow leg passes through, so junctions form
-- during vanilla's own load pass. That is why gen_routes.py carries the pixel
-- coordinate through instead of round-tripping tile->pixel->tile, and why it
-- discards any route whose legs do not share a vertex.
--
-- Verified on a live server 2026-08-13: 780 zones registered, zero
-- NullPointerExceptions, herds observed pathing normally.
function KW.rebuildJunctions()
    return true
end

-- Vanilla's own zone loader registers on OnLoadMapZones from
-- metazoneHandler.lua, which is part of the base game and therefore added to
-- the event before any mod file runs. Ours lands after it, which is what we
-- want: the map's own zones exist first, and ours are added alongside.
--
-- Zones save a "spawnedAnimals" flag once they populate, so routes added to an
-- existing save only fill in areas the animal system has not already processed.
-- On a fresh world every route spawns.
if Events and Events.OnLoadMapZones then
    Events.OnLoadMapZones.Add(KW.registerRoutes)
end
